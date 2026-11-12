defmodule Trivia.Nivel do
  def puntaje_por_tema(lineas, usuario, tema) do
    Enum.reduce(lineas, 0, fn linea, acumulado ->
      case Jason.decode(linea) do
        {:ok, %{"tema" => ^tema, "puntajes" => puntajes}} ->
          acumulado + Map.get(puntajes, usuario, 0)

        _ ->
          acumulado
      end
    end)
  end

  def nivel_por_puntaje(puntaje) when puntaje < 60, do: :basico
  def nivel_por_puntaje(puntaje) when puntaje < 180, do: :intermedio
  def nivel_por_puntaje(_puntaje), do: :avanzado

  def calcular_nivel(lineas, usuario, tema) do
    lineas
    |> puntaje_por_tema(usuario, tema)
    |> nivel_por_puntaje()
  end
end
