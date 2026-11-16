defmodule Trivia.GestorJugadores do
  use GenServer

  @prefix_bot "bot_"

  def start_link(_opciones) do
    GenServer.start_link(__MODULE__, %{sesiones_activas: %{}}, name: __MODULE__)
  end

  def init(estado) do
    Trivia.Persistencia.inicializar_almacenamiento()
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
    usuario = String.downcase(String.trim(usuario))

    cond do
      String.starts_with?(usuario, @prefix_bot) ->
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
    usuario = String.downcase(String.trim(usuario))
    nuevas_sesiones = Map.delete(estado.sesiones_activas, usuario)
    {:reply, {:ok, "Sesión cerrada"}, %{estado | sesiones_activas: nuevas_sesiones}}
  end

  def handle_call({:score, usuario}, _desde, estado) do
    usuario = String.downcase(String.trim(usuario))
    {:reply, {:ok, calcular_score(Trivia.Persistencia.stream_historial(), usuario)}, estado}
  end

  def handle_call({:ranking, tema_filtro}, _desde, estado) do
    tema_filtro =
      if is_binary(tema_filtro), do: String.downcase(String.trim(tema_filtro)), else: nil

    {:reply, {:ok, calcular_ranking(Trivia.Persistencia.stream_historial(), tema_filtro)}, estado}
  end

  # ESTADÍSTICAS (funciones puras: reciben las líneas del historial)

  @doc """
  A partir de las líneas del historial calcula el puntaje acumulado, las partidas
  jugadas y el puntaje/nivel por tema de un jugador.
  """
  def calcular_score(lineas, usuario) do
    {puntaje_total, partidas_jugadas, por_tema} =
      Enum.reduce(lineas, {0, 0, %{}}, fn linea, {pt, pj, temas} ->
        case Jason.decode(linea) do
          {:ok, %{"tema" => tema, "puntajes" => %{^usuario => puntos}}} ->
            {pt + puntos, pj + 1, Map.update(temas, tema, puntos, &(&1 + puntos))}

          _ ->
            {pt, pj, temas}
        end
      end)

    detalles_temas =
      por_tema
      |> Enum.map(fn {tema, puntos} -> {tema, puntos, Trivia.Nivel.nivel_por_puntaje(puntos)} end)
      |> Enum.sort_by(fn {tema, _, _} -> tema end)

    %{
      usuario: usuario,
      puntaje_acumulado: puntaje_total,
      partidas_jugadas: partidas_jugadas,
      temas: detalles_temas
    }
  end

  @doc """
  Ranking histórico [{jugador, puntaje, partidas}] de mayor a menor.
  Ignora a los bots y, si se da `tema_filtro`, solo cuenta las partidas de ese tema.
  """
  def calcular_ranking(lineas, tema_filtro \\ nil) do
    lineas
    |> Enum.reduce(%{}, fn linea, acc ->
      case Jason.decode(linea) do
        {:ok, %{"tema" => tema, "puntajes" => puntajes}} ->
          if is_nil(tema_filtro) or tema == tema_filtro do
            Enum.reduce(puntajes, acc, fn {jugador, puntos}, inner ->
              if String.starts_with?(jugador, @prefix_bot) do
                inner
              else
                {pt, pj} = Map.get(inner, jugador, {0, 0})
                Map.put(inner, jugador, {pt + puntos, pj + 1})
              end
            end)
          else
            acc
          end

        _ ->
          acc
      end
    end)
    |> Enum.map(fn {jugador, {puntos, partidas}} -> {jugador, puntos, partidas} end)
    |> Enum.sort_by(fn {jugador, puntos, _} -> {-puntos, jugador} end)
  end

  def handle_cast({:desconectar_por_pid, cliente_pid}, estado) do
    usuario_encontrado =
      Enum.find_value(estado.sesiones_activas, fn {usr, pid} ->
        if pid == cliente_pid, do: usr
      end)

    nuevas_sesiones =
      if usuario_encontrado do
        Map.delete(estado.sesiones_activas, usuario_encontrado)
      else
        estado.sesiones_activas
      end

    {:noreply, %{estado | sesiones_activas: nuevas_sesiones}}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, estado) do
    GenServer.cast(__MODULE__, {:desconectar_por_pid, pid})
    {:noreply, estado}
  end

  # FUNCIONES PRIVADAS

  defp usuario_conectado_en_otro_lado?(sesiones, usuario) do
    Enum.any?(sesiones, fn {usr, _pid} -> usr == usuario end)
  end

  defp validar_o_registrar_usuario(usuario, clave) do
    case Trivia.Persistencia.leer_usuarios() do
      {:ok, lista} ->
        encontrado = Enum.find(lista, fn u -> u["usuario"] == usuario end)

        cond do
          is_nil(encontrado) ->
            Trivia.Persistencia.guardar_usuario(usuario, clave)

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
