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
    lineas = Trivia.Persistencia.stream_historial()

    {puntaje_total, partidas_jugadas, por_tema} =
      Enum.reduce(lineas, {0, 0, %{}}, fn linea, {pt, pj, temas_acc} ->
        case Jason.decode(linea) do
          {:ok, %{"tema" => tema, "puntajes" => puntajes}} ->
            if Map.has_key?(puntajes, usuario) do
              puntos = Map.get(puntajes, usuario)
              nuevo_pt = pt + puntos
              nuevo_pj = pj + 1

              actual_tema = Map.get(temas_acc, tema, 0)
              nuevo_tema_puntos = actual_tema + puntos
              nuevo_temas = Map.put(temas_acc, tema, nuevo_tema_puntos)

              {nuevo_pt, nuevo_pj, nuevo_temas}
            else
              {pt, pj, temas_acc}
            end

          _ ->
            {pt, pj, temas_acc}
        end
      end)

    detalles_temas =
      Enum.map(por_tema, fn {tema, puntos} ->
        nivel = Trivia.Nivel.nivel_por_puntaje(puntos)
        {tema, puntos, nivel}
      end)

    resultado = %{
      usuario: usuario,
      puntaje_acumulado: puntaje_total,
      partidas_jugadas: partidas_jugadas,
      temas: detalles_temas
    }

    {:reply, {:ok, resultado}, estado}
  end

  def handle_call({:ranking, tema_filtro}, _desde, estado) do
    lineas = Trivia.Persistencia.stream_historial()

    estadisticas =
      Enum.reduce(lineas, %{}, fn linea, acc ->
        case Jason.decode(linea) do
          {:ok, %{"tema" => tema, "puntajes" => puntajes}} ->
            if is_nil(tema_filtro) or tema == tema_filtro do
              Enum.reduce(puntajes, acc, fn {jugador, puntos}, inner_acc ->
                # Ignorar bots en el ranking histórico según sección 6.6
                if String.starts_with?(jugador, "bot_") do
                  inner_acc
                else
                  {pt_actual, pj_actual} = Map.get(inner_acc, jugador, {0, 0})
                  Map.put(inner_acc, jugador, {pt_actual + puntos, pj_actual + 1})
                end
              end)
            else
              acc
            end

          _ ->
            acc
        end
      end)

    ranking_ordenado =
      estadisticas
      |> Enum.map(fn {jugador, {puntos, partidas}} -> {jugador, puntos, partidas} end)
      |> Enum.sort_by(fn {_j, puntos, _p} -> -puntos end)

    {:reply, {:ok, ranking_ordenado}, estado}
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
