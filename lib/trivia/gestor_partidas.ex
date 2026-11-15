defmodule Trivia.GestorPartidas do
  use GenServer

  def start_link(_opciones) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(estado_inicial) do
    {:ok, estado_inicial}
  end

  def handle_call({:crear_partida, usuario, tema, preguntas, tiempo, cliente_pid}, _desde, estado) do
    tema = String.downcase(String.trim(tema))

    if usuario_en_partida?(estado, usuario) do
      {:reply, {:error, "create_game ejecutado por un jugador que ya está en una partida"},
       estado}
    else
      nivel =
        Trivia.Persistencia.stream_historial()
        |> Trivia.Nivel.calcular_nivel(usuario, tema)

      {n_bas, n_inter, n_av} = Trivia.BancoPreguntas.calcular_reparto(nivel, preguntas)

      requeridas_por_nivel = [basico: n_bas, intermedio: n_inter, avanzado: n_av]
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
             Trivia.BancoPreguntas.validar_disponibilidad_tema(tema, requeridas_por_nivel),
           {:ok, _datos} <-
             Trivia.Structs.Partida.nuevo(id, usuario, tema, nivel, preguntas, tiempo),
           {:ok, pid} <- Trivia.SupervisorPartidas.iniciar_partida(opciones) do
        info = %{pid: pid, creador: usuario, cliente_pid: cliente_pid}
        {:reply, {:ok, id, nivel}, Map.put(estado, id, info)}
      else
        {:error, razon} -> {:reply, {:error, razon}, estado}
      end
    end
  end

  def handle_call({:add_bot, id_partida, dificultad}, _desde, estado) do
    case Map.get(estado, id_partida) do
      nil ->
        {:reply, {:error, "La partida no existe"}, estado}

      info ->
        partida_pid = info.pid
        partida_actual = Trivia.Partida.consultar(partida_pid)

        cond do
          partida_actual.estado != :esperando ->
            {:reply, {:error, "add_bot con la partida ya iniciada"}, estado}

          length(partida_actual.jugadores) >= 4 ->
            {:reply, {:error, "add_bot con la partida llena"}, estado}

          true ->
            n_bots = length(partida_actual.jugadores) - 1
            nombre_bot = "bot_#{n_bots + 1}"

            case Trivia.Bot.start_link(
                   nombre: nombre_bot,
                   dificultad: String.to_atom(dificultad),
                   partida_pid: partida_pid
                 ) do
              {:ok, bot_pid} ->
                case Trivia.Partida.agregar_bot(partida_pid, nombre_bot, bot_pid) do
                  :ok -> {:reply, {:ok, nombre_bot}, estado}
                  {:error, razon} -> {:reply, {:error, razon}, estado}
                end

              {:error, razon} ->
                {:reply, {:error, razon}, estado}
            end
        end
    end
  end

  def handle_call({:start_game, id_partida}, _desde, estado) do
    case Map.get(estado, id_partida) do
      nil ->
        {:reply, {:error, "La partida no existe"}, estado}

      info ->
        partida_pid = info.pid
        partida_actual = Trivia.Partida.consultar(partida_pid)
        n_bots = length(partida_actual.jugadores) - 1

        cond do
          partida_actual.estado != :esperando ->
            {:reply, {:error, "La partida ya fue iniciada"}, estado}

          n_bots < 2 ->
            {:reply, {:error, "start_game con menos de dos bots en la partida"}, estado}

          true ->
            case Trivia.Partida.iniciar(partida_pid) do
              {:ok, res} -> {:reply, {:ok, res}, estado}
              {:error, razon} -> {:reply, {:error, razon}, estado}
            end
        end
    end
  end

  def handle_call({:responder, id_partida, usuario, respuesta}, _desde, estado) do
    case Map.get(estado, id_partida) do
      nil ->
        {:reply, {:error, "Partida no encontrada"}, estado}

      info ->
        resultado = Trivia.Partida.responder(info.pid, usuario, respuesta)
        {:reply, resultado, estado}
    end
  end

  def handle_call({:leave_game, id_partida, _usuario}, _desde, estado) do
    case Map.get(estado, id_partida) do
      nil ->
        {:reply, {:error, "Partida no encontrada"}, estado}

      info ->
        DynamicSupervisor.terminate_child(Trivia.SupervisorPartidas, info.pid)
        {:reply, :ok, Map.delete(estado, id_partida)}
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
    Trivia.Persistencia.registrar_resultado(linea_historial(resultado))
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

    Trivia.Persistencia.registrar_resultado(linea_historial(resultado))
    {:noreply, Map.delete(estado, partida.id)}
  end

  def handle_cast({:partida_cancelada, id}, estado) do
    case Map.get(estado, id) do
      %{cliente_pid: cliente_pid} ->
        send(cliente_pid, {:partida_cancelada, id})

      _ ->
        :ok
    end

    {:noreply, Map.delete(estado, id)}
  end

  def handle_cast(_otro_aviso, estado), do: {:noreply, estado}

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

    if Map.has_key?(estado, id) do
      generar_id(estado)
    else
      id
    end
  end

  def usuario_en_partida?(estado, usuario) do
    Enum.any?(estado, fn {_id, info} -> info.creador == usuario end)
  end
end
