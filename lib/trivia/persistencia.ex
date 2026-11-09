defmodule Trivia.Persistencia do
  @dir_data "data"
  @users_file Path.join(@dir_data, "users.json")
  @questions_file Path.join(@dir_data, "questions.json")
  @results_file Path.join(@dir_data, "results.log")

  @doc """
  Asegura que la carpeta de datos y los archivos base existan.
  """
  def inicializar_almacenamiento do
    File.mkdir_p!(@dir_data)
    if not File.exists?(@users_file), do: File.write!(@users_file, "[]")
    if not File.exists?(@results_file), do: File.write!(@results_file, "")
  end

  # GESTIÓN DE USERS.JSON

  def leer_usuarios do
    inicializar_almacenamiento()

    case File.read(@users_file) do
      {:ok, contenido} ->
        case Jason.decode(contenido) do
          {:ok, lista} -> {:ok, lista}
          {:error, _} -> {:error, "Error al decodificar users.json"}
        end

      {:error, _} ->
        {:error, "No se pudo leer el archivo de usuarios"}
    end
  end

  def guardar_usuario(usuario, clave) do
    inicializar_almacenamiento()

    with {:ok, usuarios} <- leer_usuarios() do
      nuevo_registro = %{"usuario" => usuario, "clave" => clave}
      nueva_lista = [nuevo_registro | usuarios]

      case Jason.encode(nueva_lista, pretty: true) do
        {:ok, json_data} ->
          File.write!(@users_file, json_data)
          :ok

        {:error, _} ->
          {:error, "Error al codificar el usuario para JSON"}
      end
    end
  end

  # GESTIÓN DE QUESTIONS.JSON

  def leer_banco_preguntas do
    if File.exists?(@questions_file) do
      case File.read(@questions_file) do
        {:ok, contenido} ->
          case Jason.decode(contenido) do
            {:ok, lista} -> {:ok, lista}
            {:error, _} -> {:error, "El archivo questions.json tiene un formato JSON inválido"}
          end

        {:error, _} ->
          {:error, "No se pudo leer questions.json"}
      end
    else
      {:error, "El archivo questions.json no existe en la carpeta data/"}
    end
  end

  # GESTIÓN DE RESULTS.LOG (Historial con Streams)

  def registrar_resultado(linea_resultado) do
    inicializar_almacenamiento()
    # Se agrega una línea al final del archivo de texto plano de forma segura
    File.write!(@results_file, "#{linea_resultado}\n", [:append])
  end

  @doc """
  Retorna un Stream perezoso que lee las líneas de results.log
  para calcular puntajes, niveles y rankings sin saturar memoria.
  """
  def stream_historial do
    inicializar_almacenamiento()

    if File.exists?(@results_file) do
      File.stream!(@results_file)
      |> Stream.map(&String.trim/1)
      |> Stream.reject(&(&1 == ""))
    else
      Stream.empty()
    end
  end
end
