defmodule Trivia.BotTest do
  use ExUnit.Case
  alias Trivia.Bot

  test "decision de un bot devuelve opcion valida (A-D) y retardo segun dificultad" do
    pregunta = %{
      nivel: :basico,
      tiempo: 15
    }

    respuesta_correcta = "B"

    # Dificultad fácil (40% a 90% de 15s -> 6000ms a 13500ms)
    {letra_facil, delay_facil} = Bot.decidir_respuesta(pregunta, respuesta_correcta, :facil)
    assert letra_facil in ["A", "B", "C", "D"]
    assert delay_facil >= 6000 and delay_facil <= 13500

    # Dificultad difícil (10% a 40% de 15s -> 1500ms a 6000ms)
    {letra_dificil, delay_dificil} = Bot.decidir_respuesta(pregunta, respuesta_correcta, :dificil)
    assert letra_dificil in ["A", "B", "C", "D"]
    assert delay_dificil >= 1500 and delay_dificil <= 6000
  end

  test "es_bot? reconoce solo nombres con el prefijo reservado" do
    assert Bot.es_bot?("bot_1")
    refute Bot.es_bot?("pedro")
    refute Bot.es_bot?("robot_1")
    refute Bot.es_bot?(nil)
  end

  test "nombre/1 genera los nombres bot_1, bot_2..." do
    assert Bot.nombre(1) == "bot_1"
    assert Bot.nombre(3) == "bot_3"
    assert Bot.es_bot?(Bot.nombre(2))
  end

  test "parsear_dificultad solo acepta facil y dificil" do
    assert Bot.parsear_dificultad("facil") == {:ok, :facil}
    assert Bot.parsear_dificultad("dificil") == {:ok, :dificil}
    assert {:error, _} = Bot.parsear_dificultad("medio")
    assert {:error, _} = Bot.parsear_dificultad("")
  end

  test "el bot se detiene solo cuando su partida termina" do
    partida_falsa = spawn(fn -> Process.sleep(:infinity) end)

    {:ok, bot} =
      Bot.iniciar(nombre: "bot_1", dificultad: :facil, partida_pid: partida_falsa)

    ref = Process.monitor(bot)
    Process.exit(partida_falsa, :kill)

    assert_receive {:DOWN, ^ref, :process, ^bot, :normal}, 1_000
  end
end
