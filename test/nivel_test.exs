defmodule Trivia.NivelTest do
  use ExUnit.Case, async: true
  alias Trivia.Nivel

  test "nivel_por_puntaje evalúa umbrales exactos y puntajes negativos" do
    assert Nivel.nivel_por_puntaje(-15) == :basico
    assert Nivel.nivel_por_puntaje(0) == :basico
    assert Nivel.nivel_por_puntaje(59) == :basico
    assert Nivel.nivel_por_puntaje(60) == :intermedio
    assert Nivel.nivel_por_puntaje(179) == :intermedio
    assert Nivel.nivel_por_puntaje(180) == :avanzado
    assert Nivel.nivel_por_puntaje(500) == :avanzado
  end

  test "calculo de nivel desde el historial evaluando umbrales y temas nunca jugados" do
    lineas_historial = [
      Jason.encode!(%{"tema" => "ciencia", "puntajes" => %{"pedro" => 40}}),
      # Total 65 -> intermedio
      Jason.encode!(%{"tema" => "ciencia", "puntajes" => %{"pedro" => 25}}),
      # Negativo -> basico
      Jason.encode!(%{"tema" => "historia", "puntajes" => %{"pedro" => -10}})
    ]

    # Tema ciencia: 40 + 25 = 65 (intermedio)
    assert Nivel.calcular_nivel(lineas_historial, "pedro", "ciencia") == :intermedio

    # Tema historia: -10 (< 60, básico)
    assert Nivel.calcular_nivel(lineas_historial, "pedro", "historia") == :basico

    # Tema nunca jugado (devuelve 0 puntaje -> básico)
    assert Nivel.calcular_nivel(lineas_historial, "pedro", "matematicas") == :basico
  end
end
