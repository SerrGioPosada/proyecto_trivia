defmodule Trivia.GestorPartidas do
  use GenServer

  alias Trivia.{BancoPreguntas, Bot, Nivel, Partida, Persistencia, SupervisorPartidas}

  @max_jugadores 4
  @min_bots 2

  def start_link(_opciones) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(estado_inicial) do
    {:ok, estado_inicial}
  end

  # API PUBLICA

  def crear_partida(usuario, tema, preguntas, tiempo, cliente_pid) do
    GenServer.call(
      __MODULE__,
      {:crear_partida, usuario, tema, preguntas, tiempo, cliente_pid}
    )
  end

  def agregar_bot(id_partida, dificultad) do
    GenServer.call(__MODULE__, {:add_bot, id_partida, dificultad})
  end

  def iniciar_partida(id_partida) do
    GenServer.call(__MODULE__, {:start_game, id_partida})
  end

  def responder(id_partida, usuario, letra) do
    GenServer.call(__MODULE__, {:responder, id_partida, usuario, letra})
  end

  def abandonar_partida(id_partida, usuario) do
    GenServer.call(__MODULE__, {:leave_game, id_partida, usuario})
  end

  # CALLBACKS GENSERVER

  def handle_call({:crear_partida, usuario, tema, preguntas, tiempo, cliente_pid}, _desde, estado) do
    with :ok <- validar_parametros(tema, preguntas, tiempo),
         tema = normalizar_tema(tema),
         :ok <- validar_usuario_libre(estado, usuario),
         nivel = calcular_nivel_jugador(usuario, tema),
         {n_bas, n_inter, n_av} = BancoPreguntas.calcular_reparto(nivel, preguntas),
         {:ok, :suficientes_preguntas} <-
           BancoPreguntas.validar_disponibilidad_tema(
             tema,
             basico: n_bas,
             intermedio: n_inter,
             avanzado: n_av
           ),
         id = generar_id(estado),
         # Partida.init valida los datos con Structs.Partida.nuevo/6
         {:ok, pid} <-
           SupervisorPartidas.iniciar_partida(
             id: id,
             creador: usuario,
             tema: tema,
             nivel: nivel,
             total_preguntas: preguntas,
             tiempo_pregunta: tiempo,
             cliente_pid: cliente_pid
           ) do
      info = %{pid: pid, creador: usuario, cliente_pid: cliente_pid}
      {:reply, {:ok, id, nivel}, Map.put(estado, id, info)}
    else
      {:error, razon} -> {:reply, {:error, razon}, estado}
    end
  end

  def handle_call({:add_bot, id_partida, dificultad}, _desde, estado) do
    respuesta =
      with {:ok, info} <- buscar_partida(estado, id_partida, "La partida no existe"),
           {:ok, dificultad} <- Bot.parsear_dificultad(dificultad),
           {:ok, partida} <- consultar_partida(info.pid),
           :ok <- validar_cupo_bot(partida) do
        crear_y_registrar_bot(info.pid, partida, dificultad)
      end

    {:reply, respuesta, estado}
  end

  def handle_call({:start_game, id_partida}, _desde, estado) do
    respuesta =
      with {:ok, info} <- buscar_partida(estado, id_partida, "La partida no existe"),
           {:ok, partida} <- consultar_partida(info.pid),
           :ok <- validar_inicio(partida) do
        seguro(fn -> Partida.iniciar(info.pid) end)
      end

    {:reply, respuesta, estado}
  end

  def handle_call({:responder, id_partida, usuario, respuesta}, _desde, estado) do
    resultado =
      with {:ok, info} <- buscar_partida(estado, id_partida, "Partida no encontrada") do
        seguro(fn -> Partida.responder(info.pid, usuario, respuesta) end)
      end

    {:reply, resultado, estado}
  end

  def handle_call({:leave_game, id_partida, usuario}, _desde, estado) do
    with {:ok, info} <- buscar_partida(estado, id_partida, "Partida no encontrada"),
         :ok <- validar_creador(info, usuario) do
      SupervisorPartidas.terminar_partida(info.pid)
      {:reply, :ok, Map.delete(estado, id_partida)}
    else
      {:error, razon} -> {:reply, {:error, razon}, estado}
    end
  end

  def handle_cast({:actualizar_pid_partida, id, pid}, estado) do
    info = Map.get(estado, id)

    cond do
      info == nil ->
        {:noreply, estado}

      info.pid == pid ->
        {:noreply, estado}

      true ->
        send(info.cliente_pid, {:partida_reiniciada, id})
        {:noreply, Map.put(estado, id, %{info | pid: pid})}
    end
  end

  def handle_cast({:partida_terminada, partida, resultado}, estado) do
    Persistencia.registrar_resultado(linea_historial(resultado))
    {:noreply, Map.delete(estado, partida.id)}
  end

  def handle_cast({:partida_abandonada, partida}, estado) do
    ranking = Enum.sort_by(partida.puntajes, fn {_jugador, puntos} -> -puntos end)
    {_, maximo} = hd(ranking)
    ganadores = for {jugador, puntos} <- ranking, puntos == maximo, do: jugador

    resultado = %{
      id: partida.id,
      tema: partida.tema,
      nivel: partida.nivel,
      ranking: ranking,
      ganadores: ganadores
    }

    Persistencia.registrar_resultado(linea_historial(resultado))
    {:noreply, Map.delete(estado, partida.id)}
  end

  # La partida en espera se cerró porque su creador se desconectó
  # (el cliente ya no existe, no hay a quién avisar).
  def handle_cast({:partida_cancelada, id}, estado) do
    {:noreply, Map.delete(estado, id)}
  end

  def handle_cast(_otro_aviso, estado), do: {:noreply, estado}

  # VALIDACIONES

  defp validar_parametros(tema, preguntas, tiempo) do
    cond do
      not is_binary(tema) or String.trim(tema) == "" ->
        {:error, "Debes indicar el tema: create_game tema=<tema> preguntas=<n> tiempo=<s>"}

      not is_integer(preguntas) or preguntas < 1 ->
        {:error, "El número de preguntas debe ser un entero positivo"}

      not is_integer(tiempo) or tiempo < 1 ->
        {:error, "El tiempo por pregunta debe ser un entero positivo"}

      true ->
        :ok
    end
  end

  defp validar_usuario_libre(estado, usuario) do
    if usuario_en_partida?(estado, usuario) do
      {:error, "create_game ejecutado por un jugador que ya está en una partida"}
    else
      :ok
    end
  end

  defp validar_cupo_bot(partida) do
    cond do
      partida.estado != :esperando -> {:error, "add_bot con la partida ya iniciada"}
      length(partida.jugadores) >= @max_jugadores -> {:error, "add_bot con la partida llena"}
      true -> :ok
    end
  end

  defp validar_inicio(partida) do
    n_bots = length(partida.jugadores) - 1

    cond do
      partida.estado != :esperando ->
        {:error, "La partida ya fue iniciada"}

      n_bots < @min_bots ->
        {:error, "start_game con menos de dos bots en la partida"}

      true ->
        :ok
    end
  end

  defp validar_creador(info, usuario) do
    if info.creador == usuario do
      :ok
    else
      {:error, "Solo el creador puede abandonar la partida"}
    end
  end

  # BOTS

  defp crear_y_registrar_bot(partida_pid, partida, dificultad) do
    nombre = Bot.nombre(length(partida.jugadores))

    # Bot.iniciar/1 no enlaza al bot con este gestor; la Partida lo enlaza
    # al registrarlo.
    with {:ok, bot_pid} <-
           Bot.iniciar(nombre: nombre, dificultad: dificultad, partida_pid: partida_pid) do
      case seguro(fn -> Partida.agregar_bot(partida_pid, nombre, bot_pid) end) do
        :ok ->
          {:ok, nombre}

        {:error, razon} ->
          # Evita dejar un bot huérfano si la partida lo rechazó
          GenServer.stop(bot_pid)
          {:error, razon}
      end
    end
  end

  # AUXILIARES

  defp buscar_partida(estado, id, mensaje_no_existe) do
    case Map.get(estado, id) do
      nil -> {:error, mensaje_no_existe}
      info -> {:ok, info}
    end
  end

  defp consultar_partida(pid) do
    {:ok, Partida.consultar(pid)}
  catch
    :exit, _ -> {:error, "La partida ya no está disponible"}
  end

  # Evita que la caída de una partida arrastre a este gestor
  defp seguro(fun) do
    fun.()
  catch
    :exit, _ -> {:error, "La partida ya no está disponible"}
  end

  defp normalizar_tema(tema), do: tema |> String.trim() |> String.downcase()

  defp calcular_nivel_jugador(usuario, tema) do
    Persistencia.stream_historial()
    |> Nivel.calcular_nivel(usuario, tema)
  end

  # Línea de results.log: JSON con fecha, id, tema, nivel, ganador(es) y puntajes
  defp linea_historial(resultado) do
    Jason.encode!(%{
      "fecha" => DateTime.to_iso8601(DateTime.utc_now()),
      "id" => resultado.id,
      "tema" => resultado.tema,
      "nivel" => Atom.to_string(resultado.nivel),
      "ganador" => resultado.ganadores,
      "puntajes" => Map.new(resultado.ranking)
    })
  end

  defp generar_id(estado) do
    id = "P-#{:rand.uniform(999_999_999)}"

    if Map.has_key?(estado, id) do
      generar_id(estado)
    else
      id
    end
  end

  defp usuario_en_partida?(estado, usuario) do
    Enum.any?(estado, fn {_id, info} -> info.creador == usuario end)
  end
end
