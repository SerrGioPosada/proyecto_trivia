defmodule Trivia.Partida do
  use GenServer

  alias Trivia.Structs.Partida

  # INICIO DEL PROCESO

  @doc """
  Inicia el proceso independiente de una partida.
  """
  def start_link(opciones) do
    GenServer.start_link(__MODULE__, opciones)
  end

  @doc """
  Define como debe comportarse el proceso cuando falla.
  """
  def child_spec(opciones) do
    %{
      id: {__MODULE__, Keyword.fetch!(opciones, :id)},
      start: {__MODULE__, :start_link, [opciones]},
      restart: :transient,
      shutdown: 5000,
      type: :worker
    }
  end

  @doc """
  Inicializa el estado de la partida.
  """
  def init(opciones) do
    Process.flag(:trap_exit, true)

    id = Keyword.fetch!(opciones, :id)
    creador = Keyword.fetch!(opciones, :creador)
    tema = Keyword.fetch!(opciones, :tema)
    nivel = Keyword.get(opciones, :nivel, :basico)
    total_preguntas = Keyword.fetch!(opciones, :total_preguntas)
    tiempo_pregunta = Keyword.fetch!(opciones, :tiempo_pregunta)
    cliente_pid = Keyword.fetch!(opciones, :cliente_pid)

    with true <- is_pid(cliente_pid),
         {:ok, partida} <-
           Partida.nuevo(
             id,
             creador,
             tema,
             nivel,
             total_preguntas,
             tiempo_pregunta
           ) do
      referencia_cliente = Process.monitor(cliente_pid)

      estado = %{
        partida: partida,
        cliente_pid: cliente_pid,
        referencia_cliente: referencia_cliente,
        jugadores_pid: %{creador => cliente_pid},
        bots_pid: %{},
        preguntas: [],
        respuestas: %{},
        ronda_abierta: false,
        inicio_ronda: nil,
        temporizador: nil
      }

      # Notificar al gestor el PID actual de la partida.
      # También se ejecutará si el supervisor reinicia este proceso.
      if Process.whereis(Trivia.GestorPartidas) do
        GenServer.cast(
          Trivia.GestorPartidas,
          {:actualizar_pid_partida, id, self()}
        )
      end

      {:ok, estado}
    else
      false ->
        {:stop, "El PID del cliente no es válido"}

      {:error, razon} ->
        {:stop, razon}
    end
  end

  @doc """
  Consulta los datos de una partida.
  """
  def consultar(pid) do
    GenServer.call(pid, :consultar)
  end

  @doc """
  Agrega un bot a una partida.
  """
  def agregar_bot(pid, dificultad) do
    GenServer.call(pid, {:agregar_bot, dificultad})
  end

  @doc """
  El jugador abandona la partida (leave_game / disconnect).
  En curso: se registra el resultado parcial (sección 6.5). En espera: se cancela.
  """
  def abandonar(pid) do
    GenServer.call(pid, :abandonar)
  end

  @doc """
  Solicita iniciar una partida.
  """
  def iniciar(pid) do
    GenServer.call(pid, :iniciar)
  end

  @doc """
  Consulta la siguiente pregunta pendiente de la partida.
  """
  def siguiente_pregunta(pid) do
    GenServer.call(pid, :siguiente_pregunta)
  end

  @doc """
  Registra la respuesta de un jugador en la ronda actual.
  """
  def responder(pid, jugador, respuesta) do
    GenServer.call(pid, {:responder, jugador, respuesta})
  end

  @doc """
  Cierra la ronda actual y actualiza los puntajes.
  """
  def cerrar_ronda(pid) do
    GenServer.call(pid, :cerrar_ronda)
  end

  @doc """
  Consulta los puntajes actuales de la partida.
  """
  def consultar_puntajes(pid) do
    GenServer.call(pid, :consultar_puntajes)
  end

  # CONSULTAR PARTIDA

  def handle_call(:consultar, _desde, estado) do
    {:reply, estado.partida, estado}
  end

  # CONSULTAR PUNTAJES

  def handle_call(:consultar_puntajes, _desde, estado) do
    {:reply, estado.partida.puntajes, estado}
  end

  # AGREGAR BOTS

  def handle_call({:agregar_bot, dificultad}, _desde, estado) do
    jugadores = estado.partida.jugadores

    cond do
      estado.partida.estado != :esperando ->
        {:reply, {:error, "add_bot con la partida ya iniciada"}, estado}

      length(jugadores) >= 4 ->
        {:reply, {:error, "add_bot con la partida llena"}, estado}

      match?({:error, _}, Trivia.Bot.parsear_dificultad(dificultad)) ->
        {:reply, Trivia.Bot.parsear_dificultad(dificultad), estado}

      true ->
        {:ok, dificultad_bot} = Trivia.Bot.parsear_dificultad(dificultad)
        nombre = Trivia.Bot.nombre(length(jugadores))

        # El bot se crea desde la partida, así que queda enlazado SOLO a ella:
        # muere con ella y su caída no afecta a ningún otro proceso.
        {:ok, bot_pid} =
          Trivia.Bot.start_link(
            nombre: nombre,
            dificultad: dificultad_bot,
            partida_pid: self()
          )

        nueva_partida = %{
          estado.partida
          | jugadores: jugadores ++ [nombre],
            puntajes: Map.put(estado.partida.puntajes, nombre, 0)
        }

        nuevo_estado = %{
          estado
          | partida: nueva_partida,
            bots_pid: Map.put(estado.bots_pid, nombre, bot_pid),
            jugadores_pid: Map.put(estado.jugadores_pid, nombre, bot_pid)
        }

        {:reply, {:ok, nombre}, nuevo_estado}
    end
  end

  # ABANDONAR

  def handle_call(:abandonar, _desde, estado) do
    case estado.partida.estado do
      :en_curso ->
        cancelar_temporizador(estado)
        GenServer.cast(Trivia.GestorPartidas, {:partida_abandonada, estado.partida})
        {:stop, :normal, :ok, estado}

      _ ->
        GenServer.cast(Trivia.GestorPartidas, {:partida_cancelada, estado.partida.id})
        {:stop, :normal, :ok, estado}
    end
  end

  # SIGUIENTE PREGUNTA

  def handle_call(:siguiente_pregunta, _desde, estado) do
    cond do
      estado.partida.estado != :en_curso ->
        {:reply, {:error, "La partida no está en curso"}, estado}

      estado.ronda_abierta ->
        {:reply, {:error, "La ronda actual todavía está abierta"}, estado}

      estado.partida.pregunta_actual > 0 ->
        {:reply, {:error, "Las preguntas avanzan automáticamente"}, estado}

      true ->
        {nuevo_estado, pregunta} = abrir_pregunta(estado)
        {:reply, {:ok, pregunta}, nuevo_estado}
    end
  end

  # INICIAR PARTIDA

  def handle_call(:iniciar, _desde, estado) do
    jugadores = estado.partida.jugadores

    cond do
      estado.partida.estado != :esperando ->
        {:reply, {:error, "La partida ya fue iniciada"}, estado}

      length(jugadores) < 3 ->
        {:reply, {:error, "start_game con menos de dos bots en la partida"}, estado}

      length(jugadores) > 4 ->
        {:reply, {:error, "La partida no puede tener más de 4 jugadores"}, estado}

      true ->
        {:ok, preguntas} =
          Trivia.BancoPreguntas.sortear_preguntas(
            estado.partida.tema,
            estado.partida.nivel,
            estado.partida.total_preguntas
          )

        if length(preguntas) == estado.partida.total_preguntas do
          nueva_partida = %{
            estado.partida
            | estado: :en_curso,
              pregunta_actual: 0
          }

          nuevo_estado = %{
            estado
            | partida: nueva_partida,
              preguntas: preguntas,
              respuestas: %{},
              ronda_abierta: false,
              inicio_ronda: nil,
              temporizador: nil
          }

          {estado_iniciado, _pregunta_publica} = abrir_pregunta(nuevo_estado)

          {:reply, {:ok, estado_iniciado.partida}, estado_iniciado}
        else
          {:reply, {:error, "No se pudieron seleccionar todas las preguntas"}, estado}
        end
    end
  end

  # REGISTRAR RESPUESTAS

  def handle_call({:responder, jugador, respuesta}, _desde, estado) do
    cond do
      estado.partida.estado != :en_curso ->
        {:reply, {:error, "La partida no está en curso"}, estado}

      not estado.ronda_abierta ->
        {:reply, {:error, "No hay una pregunta abierta"}, estado}

      jugador not in estado.partida.jugadores ->
        {:reply, {:error, "El jugador no pertenece a la partida"}, estado}

      Map.has_key?(estado.respuestas, jugador) ->
        {:reply, {:error, "El jugador ya respondió esta pregunta"}, estado}

      not is_binary(respuesta) ->
        {:reply, {:error, "La respuesta debe ser una letra"}, estado}

      true ->
        letra = respuesta |> String.trim() |> String.upcase()

        if letra in ["A", "B", "C", "D"] do
          numero = estado.partida.pregunta_actual
          pregunta = Enum.at(estado.preguntas, numero - 1)

          correcta = letra == pregunta.respuesta

          tiempo_transcurrido =
            System.monotonic_time(:millisecond) - estado.inicio_ronda

          tiempo_total = estado.partida.tiempo_pregunta * 1000

          tiempo_restante =
            max(0, tiempo_total - tiempo_transcurrido)

          bonificacion =
            if correcta do
              calcular_bonificacion(tiempo_restante, tiempo_total)
            else
              0
            end

          puntos =
            calcular_puntos(pregunta.nivel, correcta) + bonificacion

          nuevas_respuestas =
            Map.put(estado.respuestas, jugador, %{
              respuesta: letra,
              correcta: correcta,
              puntos: puntos,
              bonificacion: bonificacion
            })

          nuevo_estado = %{estado | respuestas: nuevas_respuestas}

          if map_size(nuevas_respuestas) ==
               length(estado.partida.jugadores) do
            send(self(), {:todos_respondieron, numero})
          end

          {:reply, {:ok, :respuesta_registrada}, nuevo_estado}
        else
          {:reply, {:error, "La respuesta debe ser A, B, C o D"}, estado}
        end
    end
  end

  # CERRAR RONDA Y ACTUALIZAR PUNTAJES

  def handle_call(:cerrar_ronda, _desde, estado) do
    cond do
      estado.partida.estado != :en_curso ->
        {:reply, {:error, "La partida no está en curso"}, estado}

      not estado.ronda_abierta ->
        {:reply, {:error, "No hay una ronda abierta"}, estado}

      true ->
        if estado.temporizador != nil do
          Process.cancel_timer(estado.temporizador)
        end

        {nuevo_estado, resultado} = finalizar_ronda(estado)

        {:reply, {:ok, resultado}, nuevo_estado}
    end
  end

  # PUNTAJE SEGUN EL NIVEL DE LA PREGUNTA

  @doc "Puntos base de una respuesta correcta (true) o incorrecta (false) según el nivel."
  def calcular_puntos(:basico, true), do: 10
  def calcular_puntos(:basico, false), do: -5
  def calcular_puntos(:intermedio, true), do: 15
  def calcular_puntos(:intermedio, false), do: -8
  def calcular_puntos(:avanzado, true), do: 20
  def calcular_puntos(:avanzado, false), do: -10

  @doc "Bonificación por rapidez: trunc(5 * restante / total), en el mismo unidad de tiempo."
  def calcular_bonificacion(restante, total), do: trunc(5 * restante / total)

  # FUNCION AUXILIAR PARA CERRAR UNA RONDA

  defp finalizar_ronda(estado) do
    numero = estado.partida.pregunta_actual
    pregunta = Enum.at(estado.preguntas, numero - 1)

    puntos_ronda =
      Enum.reduce(estado.partida.jugadores, %{}, fn jugador, acumulador ->
        puntos =
          case Map.get(estado.respuestas, jugador) do
            nil -> 0
            datos -> datos.puntos
          end

        Map.put(acumulador, jugador, puntos)
      end)

    nuevos_puntajes =
      Enum.reduce(puntos_ronda, estado.partida.puntajes, fn
        {jugador, puntos}, puntajes ->
          Map.update(puntajes, jugador, puntos, fn actual ->
            actual + puntos
          end)
      end)

    nueva_partida = %{
      estado.partida
      | puntajes: nuevos_puntajes
    }

    nuevo_estado = %{
      estado
      | partida: nueva_partida,
        ronda_abierta: false,
        inicio_ronda: nil,
        temporizador: nil
    }

    resultado = %{
      pregunta: numero,
      respuesta_correcta: pregunta.respuesta,
      respuestas: estado.respuestas,
      puntos_ronda: puntos_ronda,
      puntajes: nuevos_puntajes
    }

    {nuevo_estado, resultado}
  end

  # CIERRE CUANDO TODOS RESPONDEN

  def handle_info({:todos_respondieron, numero}, estado) do
    if estado.ronda_abierta and
         estado.partida.estado == :en_curso and
         estado.partida.pregunta_actual == numero and
         Enum.all?(
           Map.keys(estado.jugadores_pid),
           &Map.has_key?(estado.respuestas, &1)
         ) do
      if estado.temporizador != nil do
        Process.cancel_timer(estado.temporizador)
      end

      {nuevo_estado, resultado} = finalizar_ronda(estado)

      Enum.each(estado.jugadores_pid, fn {_jugador, pid} ->
        send(pid, {:ronda_finalizada, estado.partida.id, resultado})
      end)

      {:noreply, programar_siguiente_pregunta(nuevo_estado)}
    else
      {:noreply, estado}
    end
  end

  # AVANCE AUTOMATICO DE PREGUNTAS

  def handle_info({:avanzar_pregunta, numero}, estado) do
    if estado.partida.estado == :en_curso and
         not estado.ronda_abierta and
         estado.partida.pregunta_actual == numero and
         numero < estado.partida.total_preguntas do
      {nuevo_estado, _pregunta} = abrir_pregunta(estado)

      {:noreply, nuevo_estado}
    else
      {:noreply, estado}
    end
  end

  # CIERRE AUTOMATICO POR TIEMPO

  def handle_info({:tiempo_agotado, numero}, estado) do
    if estado.ronda_abierta and
         estado.partida.estado == :en_curso and
         estado.partida.pregunta_actual == numero do
      {nuevo_estado, resultado} = finalizar_ronda(estado)

      Enum.each(estado.jugadores_pid, fn {_jugador, pid} ->
        send(pid, {:ronda_finalizada, estado.partida.id, resultado})
      end)

      {:noreply, programar_siguiente_pregunta(nuevo_estado)}
    else
      {:noreply, estado}
    end
  end

  # FINALIZAR PARTIDA

  def handle_info(:finalizar_partida, estado) do
    if estado.partida.estado == :en_curso and
         not estado.ronda_abierta and
         estado.partida.pregunta_actual ==
           estado.partida.total_preguntas do
      ranking =
        estado.partida.puntajes
        |> Enum.sort_by(fn {_jugador, puntos} -> -puntos end)

      puntaje_maximo =
        ranking
        |> hd()
        |> elem(1)

      ganadores =
        ranking
        |> Enum.filter(fn {_jugador, puntos} ->
          puntos == puntaje_maximo
        end)
        |> Enum.map(fn {jugador, _puntos} -> jugador end)

      partida_finalizada = %{
        estado.partida
        | estado: :finalizada
      }

      resultado = %{
        id: partida_finalizada.id,
        tema: partida_finalizada.tema,
        nivel: partida_finalizada.nivel,
        ranking: ranking,
        ganadores: ganadores
      }

      Enum.each(estado.jugadores_pid, fn {_jugador, pid} ->
        send(pid, {:partida_finalizada, resultado})
      end)

      # Informar al gestor que la partida terminó.
      # El gestor coordinará la persistencia y liberará al jugador.
      GenServer.cast(
        Trivia.GestorPartidas,
        {:partida_terminada, partida_finalizada, resultado}
      )

      {:stop, :normal, %{estado | partida: partida_finalizada}}
    else
      {:noreply, estado}
    end
  end

  # CONTROL DE PROCESOS DE LOS BOTS
  def handle_info({:EXIT, pid, _razon}, estado) do
    nombre_bot =
      Enum.find_value(estado.bots_pid, fn {nombre, bot_pid} ->
        if bot_pid == pid, do: nombre
      end)

    case nombre_bot do
      nil ->
        {:noreply, estado}

      nombre ->
        nuevo_estado = %{
          estado
          | bots_pid: Map.delete(estado.bots_pid, nombre),
            jugadores_pid: Map.delete(estado.jugadores_pid, nombre)
        }

        if nuevo_estado.ronda_abierta do
          activos = Map.keys(nuevo_estado.jugadores_pid)

          if Enum.all?(activos, &Map.has_key?(nuevo_estado.respuestas, &1)) do
            send(self(), {:todos_respondieron, estado.partida.pregunta_actual})
          end
        end

        {:noreply, nuevo_estado}
    end
  end

  # DETECTAR DESCONEXION DEL CLIENTE
  def handle_info(
        {:DOWN, referencia, :process, pid, _razon},
        estado
      ) do
    if referencia == estado.referencia_cliente and
         pid == estado.cliente_pid do
      send(
        self(),
        {:cliente_desconectado, estado.partida.id}
      )

      {:noreply, estado}
    else
      {:noreply, estado}
    end
  end

  # FINALIZAR PARTIDA POR DESCONEXION
  def handle_info({:cliente_desconectado, id}, estado) do
    if id == estado.partida.id do
      case estado.partida.estado do
        :esperando ->
          # Si no había comenzado, cancelar sin guardar resultados.
          GenServer.cast(Trivia.GestorPartidas, {:partida_cancelada, estado.partida.id})
          {:stop, :normal, estado}

        :en_curso ->
          # Detener el temporizador de la pregunta.
          if estado.temporizador != nil do
            Process.cancel_timer(estado.temporizador)
          end

          # Avisar al gestor para que coordine el guardado.
          GenServer.cast(
            Trivia.GestorPartidas,
            {:partida_abandonada, estado.partida}
          )

          {:stop, :normal, estado}

        _ ->
          {:noreply, estado}
      end
    else
      {:noreply, estado}
    end
  end

  # Al terminar la partida (por la razón que sea) mueren sus bots.
  def terminate(_razon, estado) do
    Enum.each(estado.bots_pid, fn {_nombre, pid} -> Process.exit(pid, :shutdown) end)
    :ok
  end

  defp cancelar_temporizador(%{temporizador: nil}), do: :ok
  defp cancelar_temporizador(%{temporizador: ref}), do: Process.cancel_timer(ref)

  # PROGRAMAR SIGUIENTE PREGUNTA

  defp programar_siguiente_pregunta(estado) do
    if estado.partida.pregunta_actual <
         estado.partida.total_preguntas do
      Process.send_after(
        self(),
        {:avanzar_pregunta, estado.partida.pregunta_actual},
        3000
      )
    else
      send(self(), :finalizar_partida)
    end

    estado
  end

  # ABRIR PREGUNTA Y NOTIFICAR A LOS JUGADORES

  defp abrir_pregunta(estado) do
    numero = estado.partida.pregunta_actual + 1
    pregunta = Enum.at(estado.preguntas, numero - 1)

    tiempo_ms = estado.partida.tiempo_pregunta * 1000

    temporizador =
      Process.send_after(self(), {:tiempo_agotado, numero}, tiempo_ms)

    nueva_partida = %{
      estado.partida
      | pregunta_actual: numero
    }

    nuevo_estado = %{
      estado
      | partida: nueva_partida,
        respuestas: %{},
        ronda_abierta: true,
        inicio_ronda: System.monotonic_time(:millisecond),
        temporizador: temporizador
    }

    pregunta_publica = %{
      numero: numero,
      total: estado.partida.total_preguntas,
      tema: estado.partida.tema,
      nivel: pregunta.nivel,
      enunciado: pregunta.enunciado,
      opciones: pregunta.opciones,
      tiempo: estado.partida.tiempo_pregunta
    }

    Enum.each(estado.jugadores_pid, fn {jugador, pid} ->
      if String.starts_with?(jugador, "bot_") do
        send(pid, {:pregunta_bot, estado.partida.id, pregunta_publica, pregunta.respuesta})
      else
        send(pid, {:nueva_pregunta, estado.partida.id, pregunta_publica})
      end
    end)

    {nuevo_estado, pregunta_publica}
  end
end
