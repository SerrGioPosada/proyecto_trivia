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

  defp bot_falso do
    pid = spawn(fn -> Process.sleep(:infinity) end)
    on_exit(fn -> Process.exit(pid, :kill) end)
    pid
  end

  test "una partida nueva queda en espera con su creador" do
    {:ok, pid} = start_supervised({Partida, opciones()})
    partida = Partida.consultar(pid)

    assert partida.estado == :esperando
    assert partida.jugadores == ["ana"]
  end

  test "agregar_bot registra al bot con puntaje inicial 0" do
    {:ok, pid} = start_supervised({Partida, opciones()})

    assert :ok = Partida.agregar_bot(pid, "bot_1", bot_falso())

    partida = Partida.consultar(pid)
    assert partida.jugadores == ["ana", "bot_1"]
    assert partida.puntajes["bot_1"] == 0
  end

  test "agregar_bot rechaza nombres sin prefijo, pids invalidos y duplicados" do
    {:ok, pid} = start_supervised({Partida, opciones()})

    assert {:error, "El nombre del bot no es válido"} =
             Partida.agregar_bot(pid, "pedro", bot_falso())

    assert {:error, "El PID del bot no es válido"} = Partida.agregar_bot(pid, "bot_1", :no_pid)

    assert :ok = Partida.agregar_bot(pid, "bot_1", bot_falso())

    assert {:error, "El bot ya está registrado"} =
             Partida.agregar_bot(pid, "bot_1", bot_falso())
  end

  test "la partida admite como maximo 4 jugadores" do
    {:ok, pid} = start_supervised({Partida, opciones()})

    for n <- 1..3, do: assert(:ok = Partida.agregar_bot(pid, "bot_#{n}", bot_falso()))

    assert {:error, "La partida ya tiene el máximo de jugadores"} =
             Partida.agregar_bot(pid, "bot_4", bot_falso())
  end

  test "iniciar exige al menos 3 jugadores" do
    {:ok, pid} = start_supervised({Partida, opciones()})
    :ok = Partida.agregar_bot(pid, "bot_1", bot_falso())

    assert {:error, "Se necesitan al menos 3 jugadores"} = Partida.iniciar(pid)
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
