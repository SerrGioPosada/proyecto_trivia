defmodule Trivia.Structs.Pregunta do
  @enforce_keys [:tema, :nivel, :enunciado, :opciones, :respuesta]
  defstruct [:tema, :nivel, :enunciado, :opciones, :respuesta]

  @doc """
  Crea una estructura de Pregunta validando sus parámetros mediante un bloque with.
  """
  def nuevo(tema, nivel, enunciado, opciones, respuesta) do
    with {:ok, tema_limpio} <- validar_tema(tema),
         {:ok, nivel_limpio} <- validar_nivel(nivel),
         {:ok, enunciado_limpio} <- validar_enunciado(enunciado),
         {:ok, opciones_limpias} <- validar_opciones(opciones),
         {:ok, respuesta_limpia} <- validar_respuesta(respuesta, opciones_limpias) do
      {:ok,
       %__MODULE__{
         tema: tema_limpio,
         nivel: nivel_limpio,
         enunciado: enunciado_limpio,
         opciones: opciones_limpias,
         respuesta: respuesta_limpia
       }}
    else
      {:error, razon} -> {:error, razon}
    end
  end

  defp validar_tema(tema) when not is_binary(tema) or tema == "" do
    {:error, "El tema de la pregunta es inválido"}
  end

  defp validar_tema(tema), do: {:ok, String.downcase(String.trim(tema))}

  defp validar_nivel(nivel) when nivel in [:basico, :intermedio, :avanzado], do: {:ok, nivel}

  defp validar_nivel(nivel) when nivel in ["basico", "intermedio", "avanzado"],
    do: {:ok, String.to_atom(nivel)}

  defp validar_nivel(_),
    do: {:error, "Nivel de pregunta inválido (debe ser basico, intermedio o avanzado)"}

  defp validar_enunciado(enunciado) when not is_binary(enunciado) or enunciado == "" do
    {:error, "El enunciado de la pregunta no puede estar vacío"}
  end

  defp validar_enunciado(enunciado), do: {:ok, String.trim(enunciado)}

  defp validar_opciones(opciones) when is_list(opciones) and length(opciones) == 4 do
    {:ok, opciones}
  end

  defp validar_opciones(_),
    do: {:error, "La pregunta debe contener exactamente 4 opciones de respuesta"}

  defp validar_respuesta(respuesta, opciones) do
    resp_limpia = String.upcase(to_string(respuesta))

    if resp_limpia in ["A", "B", "C", "D"] do
      {:ok, resp_limpia}
    else
      {:error, "La respuesta correcta debe ser una letra válida entre A, B, C o D"}
    end
  end
end
