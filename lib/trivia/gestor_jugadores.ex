defmodule Trivia.GestorJugadores do
  use GenServer

  alias Trivia.{Bot, Estadisticas, Persistencia}

  def start_link(_opciones) do
    GenServer.start_link(__MODULE__, %{sesiones_activas: %{}}, name: __MODULE__)
  end

  def init(estado) do
    {:ok, estado}
  end

  # API PUBLICA

  def conectar(usuario, clave, cliente_pid) do
    GenServer.call(__MODULE__, {:conectar, usuario, clave, cliente_pid})
  end

  def desconectar(usuario) do
    GenServer.call(__MODULE__, {:desconectar, usuario})
  end

  def desconectar_por_pid(cliente_pid) do
    GenServer.cast(__MODULE__, {:desconectar_por_pid, cliente_pid})
  end

  def consultar_score(usuario) do
    GenServer.call(__MODULE__, {:score, usuario})
  end

  def consultar_ranking(tema \\ nil) do
    GenServer.call(__MODULE__, {:ranking, tema})
  end

  # CALLBACKS GENSERVER

  def handle_call({:conectar, usuario, clave, cliente_pid}, _desde, estado) do
    usuario = normalizar(usuario)

    cond do
      Bot.es_bot?(usuario) ->
        {:reply, {:error, "El usuario no puede empezar por el prefijo reservado bot_"}, estado}

      Enum.any?(estado.sesiones_activas, fn {_usr, pid} -> pid == cliente_pid end) ->
        {:reply, {:error, "Este cliente ya tiene una sesión iniciada"}, estado}

      usuario_conectado_en_otro_lado?(estado.sesiones_activas, usuario) ->
        {:reply, {:error, "El usuario ya tiene una sesión abierta en otro cliente"}, estado}

      true ->
        case validar_o_registrar_usuario(usuario, clave) do
          :ok ->
            Process.monitor(cliente_pid)
            nuevas_sesiones = Map.put(estado.sesiones_activas, usuario, cliente_pid)

            {:reply, {:ok, "Sesión iniciada correctamente como #{usuario}"},
             %{estado | sesiones_activas: nuevas_sesiones}}

          {:error, razon} ->
            {:reply, {:error, razon}, estado}
        end
    end
  end

  def handle_call({:desconectar, usuario}, _desde, estado) do
    usuario = normalizar(usuario)
    nuevas_sesiones = Map.delete(estado.sesiones_activas, usuario)
    {:reply, {:ok, "Sesión cerrada"}, %{estado | sesiones_activas: nuevas_sesiones}}
  end

  def handle_call({:score, usuario}, _desde, estado) do
    usuario = normalizar(usuario)
    resultado = Estadisticas.score(Persistencia.stream_historial(), usuario)
    {:reply, {:ok, resultado}, estado}
  end

  def handle_call({:ranking, tema_filtro}, _desde, estado) do
    tema_filtro = if is_binary(tema_filtro), do: normalizar(tema_filtro), else: tema_filtro
    ranking = Estadisticas.ranking(Persistencia.stream_historial(), tema_filtro)
    {:reply, {:ok, ranking}, estado}
  end

  def handle_cast({:desconectar_por_pid, cliente_pid}, estado) do
    nuevas_sesiones =
      estado.sesiones_activas
      |> Enum.reject(fn {_usr, pid} -> pid == cliente_pid end)
      |> Map.new()

    {:noreply, %{estado | sesiones_activas: nuevas_sesiones}}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, estado) do
    desconectar_por_pid(pid)
    {:noreply, estado}
  end

  def handle_info(_mensaje, estado), do: {:noreply, estado}

  # FUNCIONES PRIVADAS

  defp normalizar(texto), do: texto |> String.trim() |> String.downcase()

  defp usuario_conectado_en_otro_lado?(sesiones, usuario) do
    Enum.any?(sesiones, fn {usr, _pid} -> usr == usuario end)
  end

  defp validar_o_registrar_usuario(usuario, clave) do
    case Persistencia.leer_usuarios() do
      {:ok, lista} ->
        encontrado = Enum.find(lista, fn u -> u["usuario"] == usuario end)

        cond do
          is_nil(encontrado) ->
            Persistencia.guardar_usuario(usuario, clave)

          encontrado["clave"] == clave ->
            :ok

          true ->
            {:error, "Clave incorrecta al conectarse con un usuario existente"}
        end

      {:error, razon} ->
        {:error, razon}
    end
  end
end
