defmodule Trivia.Structs.Partida do
  @enforce_keys [:id, :creador, :tema]
  defstruct [
    :id,
    :creador,
    :tema,
    nivel: :basico,
    total_preguntas: 5,
    tiempo_pregunta: 15,
    jugadores: [],
    estado: :esperando,
    pregunta_actual: 0,
    puntajes: %{}
  ]

  @doc """
  Construye de manera segura el struct de la Partida validando sus parámetros con with.
  """
  def nuevo(id, creador, tema, nivel, total_preguntas, tiempo_pregunta) do
    with {:ok, id_limpio} <- validar_id(id),
         {:ok, creador_limpio} <- validar_creador(creador),
         {:ok, tema_limpio} <- validar_tema(tema),
         {:ok, n_preguntas} <- validar_total_preguntas(total_preguntas),
         {:ok, t_pregunta} <- validar_tiempo(tiempo_pregunta) do
      {:ok,
       %__MODULE__{
         id: id_limpio,
         creador: creador_limpio,
         tema: tema_limpio,
         nivel: nivel,
         total_preguntas: n_preguntas,
         tiempo_pregunta: t_pregunta,
         jugadores: [creador_limpio],
         estado: :esperando,
         pregunta_actual: 0,
         puntajes: %{creador_limpio => 0}
       }}
    else
      {:error, razon} -> {:error, razon}
    end
  end

  defp validar_id(id) when not is_binary(id) or id == "",
    do: {:error, "El ID de la partida es obligatorio"}

  defp validar_id(id), do: {:ok, String.trim(id)}

  defp validar_creador(creador) when not is_binary(creador) or creador == "",
    do: {:error, "El creador es obligatorio"}

  defp validar_creador(creador), do: {:ok, String.trim(creador)}

  defp validar_tema(tema) when not is_binary(tema) or tema == "",
    do: {:error, "El tema de la partida es obligatorio"}

  defp validar_tema(tema), do: {:ok, String.downcase(String.trim(tema))}

  defp validar_total_preguntas(total) when is_integer(total) and total > 0, do: {:ok, total}

  defp validar_total_preguntas(_),
    do: {:error, "El número total de preguntas debe ser un entero positivo"}

  defp validar_tiempo(tiempo) when is_integer(tiempo) and tiempo > 0, do: {:ok, tiempo}

  defp validar_tiempo(_),
    do: {:error, "El tiempo por pregunta debe ser un entero positivo en segundos"}
end
