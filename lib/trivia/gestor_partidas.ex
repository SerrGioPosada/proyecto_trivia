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
      {:reply, {:error, "ya esta en una partida"}, estado}
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
        total: preguntas,
        tiempo: tiempo,
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

  # La partida reporta su id y PID cada vez que arranca.
  # Si el gestor ya tenía ese id con otro PID, la partida se reinició.
  def handle_cast({:partida_iniciada, id, pid}, estado) do
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

  # La partida terminó: se guarda el resultado y el jugador queda libre.
  def handle_cast({:partida_terminada, id, resultado}, estado) do
    Trivia.Persistencia.registrar_resultado(linea_historial(resultado))
    {:noreply, Map.delete(estado, id)}
  end

  # El creador abandonó antes de iniciar: no se registra nada.
  def handle_cast({:partida_cancelada, id}, estado) do
    {:noreply, Map.delete(estado, id)}
  end

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
