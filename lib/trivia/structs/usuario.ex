defmodule Trivia.Structs.Usuario do
  @enforce_keys [:usuario, :clave]
  defstruct [:usuario, :clave]

  @doc """
  Punto de entrada para parsear o registrar un usuario con validaciones previas.
  """
  def nuevo(usuario, clave) do
    with {:ok, usuario_limpio} <- validar_usuario(usuario),
         {:ok, clave_limpia} <- validar_clave(clave) do
      {:ok, %__MODULE__{usuario: usuario_limpio, clave: clave_limpia}}
    else
      {:error, razon} -> {:error, razon}
    end
  end

  def validar_usuario(usuario) when not is_binary(usuario) do
    {:error, "El usuario debe ser una cadena de texto"}
  end

  def validar_usuario(usuario) do
    usuario_limpio = String.trim(usuario)

    cond do
      usuario_limpio == "" ->
        {:error, "El usuario no puede estar vacío"}

      String.contains?(usuario_limpio, " ") ->
        {:error, "El usuario no puede contener espacios"}

      String.starts_with?(usuario_limpio, "bot_") ->
        {:error, "El prefijo 'bot_' está reservado para jugadores automáticos"}

      true ->
        {:ok, usuario_limpio}
    end
  end

  def validar_clave(clave) when not is_binary(clave) do
    {:error, "La clave debe ser una cadena de texto"}
  end

  def validar_clave(clave) do
    clave_limpia = String.trim(clave)

    if clave_limpia == "" do
      {:error, "La clave no puede estar vacía"}
    else
      {:ok, clave_limpia}
    end
  end
end
