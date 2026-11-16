defmodule Trivia.GestorPartidas do
  use GenServer

  alias Trivia.{BancoPreguntas, Nivel, Persistencia, SupervisorPartidas}

  def start_link(_opciones) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(estado_inicial) do
    {:ok, estado_inicial}
  end

  # CREAR PARTIDA

  def handle_call({:crear_partida, usuario, tema, preguntas, tiempo, cliente_pid}, _desde, estado) do
    usuario = normalizar(usuario)
    tema = normalizar(tema)

    cond do
      usuario_en_partida?(estado, usuario) ->
        {:reply, {:error, "create_game ejecutado por un jugador que ya está en una partida"},
         estado}

      tema == "" ->
        {:reply,
         {:error, "Debes indicar un tema: create_game tema=<tema> preguntas=<n> tiempo=<s>"},
         estado}

      not (is_integer(preguntas) and preguntas > 0) ->
        {:reply, {:error, "El número de preguntas debe ser un entero positivo"}, estado}

      not (is_integer(tiempo) and tiempo > 0) ->
        {:reply, {:error, "El tiempo por pregunta debe ser un entero positivo"}, estado}

      true ->
        nivel = Nivel.calcular_nivel(Persistencia.stream_historial(), usuario, tema)
        {n_bas, n_inter, n_av} = BancoPreguntas.calcular_reparto(nivel, preguntas)
        requeridas = [basico: n_bas, intermedio: n_inter, avanzado: n_av]
        id = generar_id(estado)

        opciones = [
          id: id,
          creador: usuario,
          tema: tema,
          nivel: nivel,
          total_preguntas: preguntas,
          tiempo_pregunta: tiempo,
          cliente_pid: cliente_pid
        ]

        with {:ok, :suficientes_preguntas} <-
               BancoPreguntas.validar_disponibilidad_tema(tema, requeridas),
             {:ok, _datos} <-
               Trivia.Structs.Partida.nuevo(id, usuario, tema, nivel, preguntas, tiempo),
             {:ok, pid} <- SupervisorPartidas.iniciar_partida(opciones) do
          info = %{pid: pid, creador: usuario, cliente_pid: cliente_pid}
          {:reply, {:ok, id, nivel}, Map.put(estado, id, info)}
        else
          {:error, razon} -> {:reply, {:error, razon}, estado}
        end
    end
  end

  # AGREGAR BOT / INICIAR / RESPONDER / ABANDONAR
  # Si el proceso de la partida no está disponible (murió justo ahora),
  # el gestor no se cae: responde con un error.

  def handle_call({:add_bot, id, dificultad}, _desde, estado) do
    {:reply, con_partida(estado, id, &Trivia.Partida.agregar_bot(&1, dificultad)), estado}
  end

  def handle_call({:start_game, id}, _desde, estado) do
    respuesta =
      con_partida(estado, id, fn pid ->
        case Trivia.Partida.iniciar(pid) do
          {:ok, partida} -> {:ok, partida}
          {:error, razon} -> {:error, razon}
        end
      end)

    {:reply, respuesta, estado}
  end

  def handle_call({:responder, id, usuario, letra}, _desde, estado) do
    usuario = normalizar(usuario)
    {:reply, con_partida(estado, id, &Trivia.Partida.responder(&1, usuario, letra)), estado}
  end

  def handle_call({:leave_game, id, _usuario}, _desde, estado) do
    respuesta = con_partida(estado, id, &Trivia.Partida.abandonar/1)
    {:reply, respuesta, Map.delete(estado, id)}
  end

  # Cierra la partida abierta de un usuario (usado por disconnect)
  def handle_call({:abandonar_usuario, usuario}, _desde, estado) do
    usuario = normalizar(usuario)

    case Enum.find(estado, fn {_id, info} -> info.creador == usuario end) do
      nil ->
        {:reply, :ok, estado}

      {id, info} ->
        _ = llamar(fn -> Trivia.Partida.abandonar(info.pid) end)
        {:reply, :ok, Map.delete(estado, id)}
    end
  end

  # AVISOS DE LAS PARTIDAS (cast)

  # La partida reporta su PID al arrancar. Si el id ya existía con otro PID,
  # es un reinicio por falla: se guarda el PID nuevo y se avisa al creador.
  def handle_cast({:actualizar_pid_partida, id, pid}, estado) do
    case Map.get(estado, id) do
      nil ->
        {:noreply, estado}

      %{pid: ^pid} ->
        {:noreply, estado}

      info ->
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

    if ranking != [] do
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
    end

    {:noreply, Map.delete(estado, partida.id)}
  end

  def handle_cast({:partida_cancelada, id}, estado) do
    {:noreply, Map.delete(estado, id)}
  end

  def handle_cast(_otro_aviso, estado), do: {:noreply, estado}

  # FUNCIONES AUXILIARES

  @doc "Línea de results.log: JSON con fecha, id, tema, nivel, ganador(es) y puntajes"
  def linea_historial(resultado) do
    Jason.encode!(%{
      "fecha" => DateTime.to_iso8601(DateTime.utc_now()),
      "id" => resultado.id,
      "tema" => resultado.tema,
      "nivel" => Atom.to_string(resultado.nivel),
      "ganador" => resultado.ganadores,
      "puntajes" => Map.new(resultado.ranking)
    })
  end

  def generar_id(estado) do
    id = "P-#{:rand.uniform(999_999_999)}"
    if Map.has_key?(estado, id), do: generar_id(estado), else: id
  end

  def usuario_en_partida?(estado, usuario) do
    Enum.any?(estado, fn {_id, info} -> info.creador == usuario end)
  end

  defp con_partida(estado, id, fun) do
    case Map.get(estado, id) do
      nil -> {:error, "La partida no existe"}
      info -> llamar(fn -> fun.(info.pid) end)
    end
  end

  defp llamar(fun) do
    fun.()
  catch
    :exit, _ -> {:error, "La partida no está disponible"}
  end

  defp normalizar(texto) when is_binary(texto), do: texto |> String.trim() |> String.downcase()
  defp normalizar(_), do: ""
end
