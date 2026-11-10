defmodule Trivia.Nivel do
  def puntaje_por_tema(usuario, tema) do
    lineas = Trivia.Persistencia.stream_historial()

    Enum.reduce(lineas, 0, fn linea, acumulado ->
      case Jason.decode(linea) do
        {:ok, resultado} ->
          if Map.get(resultado, "tema") == tema do
            puntajes = Map.get(resultado, "puntajes", %{})
            puntos = Map.get(puntajes, usuario, 0)
            acumulado + puntos
          else
            acumulado
          end

        # Aquí trabajaremos con el mapa

        {:error, _} ->
          # Ignoramos la línea incorrecta
          acumulado
      end
    end)
  end

  def calcular_nivel(usuario, tema) do
    puntaje = puntaje_por_tema(usuario, tema)

    cond do
      puntaje < 60 -> :basico
      puntaje < 180 -> :intermedio
      true -> :avanzado
    end
  end
end
