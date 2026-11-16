defmodule Trivia.PartidaTest do
  use ExUnit.Case
  alias Trivia.Partida

  # PUNTAJE Y BONIFICACIÓN (funciones puras de Trivia.Partida)

  test "calculo de bonificacion por rapidez con distintos tiempos de pregunta" do
    # Caso A: tiempo_pregunta = 15s, restando 14s (14000ms de 15000ms)
    bonif_1 = Partida.calcular_bonificacion(14_000, 15_000)
    assert bonif_1 == 4

    # Puntaje correcto básico (+10) + bonificación (4) = 14
    assert Partida.calcular_puntos(:basico, true) + bonif_1 == 14

    # Caso B: tiempo_pregunta = 30s, restando 15s (15000ms de 30000ms)
    assert Partida.calcular_bonificacion(15_000, 30_000) == 2
  end

  test "la bonificacion va de 0 (sin tiempo) a 5 (respuesta inmediata)" do
    assert Partida.calcular_bonificacion(0, 15_000) == 0
    assert Partida.calcular_bonificacion(15_000, 15_000) == 5
  end

  test "puntos base por nivel acierto/error" do
    assert Partida.calcular_puntos(:basico, true) == 10
    assert Partida.calcular_puntos(:basico, false) == -5
    assert Partida.calcular_puntos(:intermedio, true) == 15
    assert Partida.calcular_puntos(:intermedio, false) == -8
    assert Partida.calcular_puntos(:avanzado, true) == 20
    assert Partida.calcular_puntos(:avanzado, false) == -10
  end

  # PROCESO DE PARTIDA (sala de espera)

  defp opciones(extra \\ []) do
    Keyword.merge(
      [
        id: "P-test-#{System.unique_integer([:positive])}",
        creador: "ana",
        tema: "ciencia",
        nivel: :basico,
        total_preguntas: 5,
        tiempo_pregunta: 15,
        cliente_pid: self()
      ],
      extra
    )
  end

  test "una partida nueva queda en espera con su creador" do
    {:ok, pid} = start_supervised({Partida, opciones()})
    partida = Partida.consultar(pid)

    assert partida.estado == :esperando
    assert partida.jugadores == ["ana"]
  end

  test "agregar_bot crea al bot con nombre bot_N y puntaje inicial 0" do
    {:ok, pid} = start_supervised({Partida, opciones()})

    assert {:ok, "bot_1"} = Partida.agregar_bot(pid, "facil")
    assert {:ok, "bot_2"} = Partida.agregar_bot(pid, "dificil")

    partida = Partida.consultar(pid)
    assert partida.jugadores == ["ana", "bot_1", "bot_2"]
    assert partida.puntajes["bot_1"] == 0
    assert partida.puntajes["bot_2"] == 0
  end

  test "agregar_bot rechaza una dificultad invalida" do
    {:ok, pid} = start_supervised({Partida, opciones()})

    assert {:error, "La dificultad debe ser facil o dificil"} = Partida.agregar_bot(pid, "medio")
    assert Partida.consultar(pid).jugadores == ["ana"]
  end

  test "la partida admite como maximo 4 jugadores" do
    {:ok, pid} = start_supervised({Partida, opciones()})

    for _ <- 1..3, do: assert({:ok, _} = Partida.agregar_bot(pid, "facil"))

    assert {:error, "add_bot con la partida llena"} = Partida.agregar_bot(pid, "facil")
  end

  test "iniciar exige al menos dos bots" do
    {:ok, pid} = start_supervised({Partida, opciones()})
    {:ok, _} = Partida.agregar_bot(pid, "facil")

    assert {:error, "start_game con menos de dos bots en la partida"} = Partida.iniciar(pid)
  end

  test "los bots mueren junto con su partida" do
    opts = opciones()
    {:ok, pid} = start_supervised({Partida, opts})
    {:ok, _} = Partida.agregar_bot(pid, "facil")

    bots = :sys.get_state(pid).bots_pid |> Map.values()
    assert length(bots) == 1
    assert Enum.all?(bots, &Process.alive?/1)
    refs = for bot <- bots, do: Process.monitor(bot)

    stop_supervised!({Partida, opts[:id]})
    for ref <- refs, do: assert_receive({:DOWN, ^ref, :process, _, _}, 1_000)
  end

  test "no se puede responder si la partida no esta en curso" do
    {:ok, pid} = start_supervised({Partida, opciones()})

    assert {:error, "La partida no está en curso"} = Partida.responder(pid, "ana", "A")
  end

  test "si el creador se desconecta mientras la partida espera, la partida se cierra" do
    cliente = spawn(fn -> Process.sleep(:infinity) end)
    {:ok, pid} = start_supervised({Partida, opciones(cliente_pid: cliente)})

    ref = Process.monitor(pid)
    Process.exit(cliente, :kill)

    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1_000
  end
end
