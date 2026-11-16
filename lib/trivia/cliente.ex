defmodule Trivia.Cliente do
  @servidor_nombre Trivia.Servidor

  def iniciar_cliente(nodo_servidor) do
    Node.connect(nodo_servidor)
    {:ok, receptor_pid} = Trivia.Receptor.start_link([])

    IO.puts("=== CLIENTE DE TRIVIA CONECTADO ===")

    bucle_comandos(%{
      usuario: nil,
      partida_id: nil,
      receptor_pid: receptor_pid,
      servidor: {@servidor_nombre, nodo_servidor}
    })
  end

  defp bucle_comandos(estado) do
    IO.write("\nComando > ")

    entrada =
      case IO.gets("") do
        texto when is_binary(texto) ->
          String.trim(texto)

        _fin_de_entrada ->
          IO.puts("Saliendo del cliente...")
          exit(:normal)
      end

    partes = String.split(entrada)

    nuevo_estado =
      case partes do
        ["connect", usuario, clave] ->
          manejar_connect(usuario, clave, estado)

        ["create_game" | args] ->
          manejar_create_game(args, estado)

        ["add_bot", dificultad] ->
          manejar_add_bot(dificultad, estado)

        ["start_game"] ->
          manejar_start_game(estado)

        ["answer", letra] ->
          manejar_answer(letra, estado)

        ["score"] ->
          manejar_score(estado)

        ["ranking" | args] ->
          manejar_ranking(args, estado)

        ["leave_game"] ->
          manejar_leave_game(estado)

        ["disconnect"] ->
          manejar_disconnect(estado)

        ["exit"] ->
          IO.puts("Saliendo del cliente...")
          exit(:normal)

        _ ->
          IO.puts("Comando desconocido o sintaxis incorrecta.")
          estado
      end

    bucle_comandos(nuevo_estado)
  end

  defp manejar_connect(usuario, clave, estado) do
    # El servidor guarda los usuarios en minúsculas; el cliente debe usar
    # exactamente el mismo nombre para crear partidas, responder y consultar.
    usuario = String.downcase(usuario)

    case Node.ping(elem(estado.servidor, 1)) do
      :pong ->
        case GenServer.call(estado.servidor, {:connect, usuario, clave, estado.receptor_pid}) do
          {:ok, msg} ->
            IO.puts(msg)
            %{estado | usuario: usuario}

          {:error, razon} ->
            IO.puts("Error: #{texto_error(razon)}")
            estado
        end

      :pang ->
        IO.puts("Error: Servidor no disponible cuando el cliente intenta conectarse.")
        estado
    end
  end

  defp manejar_create_game(args, estado) do
    if is_nil(estado.usuario) do
      IO.puts("Error: Comando ejecutado sin haber iniciado sesión.")
      estado
    else
      parsed = parse_args(args)

      with {:ok, tema} <- obtener_tema(parsed),
           {:ok, preguntas} <- obtener_entero(parsed, "preguntas", 5),
           {:ok, tiempo} <- obtener_entero(parsed, "tiempo", 15) do
        crear_partida(estado, tema, preguntas, tiempo)
      else
        {:error, razon} ->
          IO.puts("Error al crear partida: #{razon}")
          estado
      end
    end
  end

  defp crear_partida(estado, tema, preguntas, tiempo) do
    peticion = {:crear_partida, estado.usuario, tema, preguntas, tiempo, estado.receptor_pid}

    case GenServer.call(estado.servidor, peticion) do
      {:ok, id, nivel} ->
        IO.puts("Partida creada exitosamente. ID: #{id} | Nivel del creador en #{tema}: #{nivel}")

        %{estado | partida_id: id}

      {:error, razon} ->
        IO.puts("Error al crear partida: #{texto_error(razon)}")
        estado
    end
  end

  defp manejar_add_bot(dificultad, estado) do
    if is_nil(estado.partida_id) do
      IO.puts("Error: add_bot ejecutado sin estar en una partida.")
      estado
    else
      case GenServer.call(estado.servidor, {:add_bot, estado.partida_id, dificultad}) do
        {:ok, nombre_bot} ->
          IO.puts("Bot agregado con éxito: #{nombre_bot}")
          estado

        {:error, razon} ->
          IO.puts("Error: #{texto_error(razon)}")
          estado
      end
    end
  end

  defp manejar_start_game(estado) do
    if is_nil(estado.partida_id) do
      IO.puts("Error: start_game ejecutado sin estar en una partida.")
      estado
    else
      case GenServer.call(estado.servidor, {:start_game, estado.partida_id}) do
        {:ok, _partida} ->
          IO.puts("¡Partida iniciada!")
          estado

        {:error, razon} ->
          IO.puts("Error al iniciar: #{texto_error(razon)}")
          estado
      end
    end
  end

  defp manejar_answer(letra, estado) do
    if is_nil(estado.partida_id) do
      IO.puts("Error: No estás en una partida activa.")
      estado
    else
      case GenServer.call(estado.servidor, {:responder, estado.partida_id, estado.usuario, letra}) do
        {:ok, :respuesta_registrada} ->
          IO.puts("Respuesta registrada.")
          estado

        {:error, razon} ->
          IO.puts("Error: #{texto_error(razon)}")
          estado
      end
    end
  end

  defp manejar_score(estado) do
    if is_nil(estado.usuario) do
      IO.puts("Error: Comando ejecutado sin haber iniciado sesión.")
      estado
    else
      case GenServer.call(estado.servidor, {:score, estado.usuario}) do
        {:ok, datos} ->
          IO.puts("\n=== #{datos.usuario} ===")
          IO.puts("Puntaje acumulado: #{datos.puntaje_acumulado}")
          IO.puts("Partidas jugadas: #{datos.partidas_jugadas}")
          IO.puts("\nTema        Puntaje   Nivel")

          Enum.each(datos.temas, fn {t, p, n} ->
            IO.puts("#{String.pad_trailing(t, 12)} #{String.pad_trailing(to_string(p), 9)} #{n}")
          end)

          estado

        {:error, razon} ->
          IO.puts("Error: #{texto_error(razon)}")
          estado
      end
    end
  end

  defp manejar_ranking(args, estado) do
    tema = List.first(args)

    case GenServer.call(estado.servidor, {:ranking, tema}) do
      {:ok, lista} ->
        titulo = if tema, do: "=== Ranking global (#{tema}) ===", else: "=== Ranking global ==="
        IO.puts("\n#{titulo}")
        IO.puts("#    Jugador     Puntaje    Partidas")

        lista
        |> Enum.with_index(1)
        |> Enum.each(fn {{jugador, puntos, partidas}, idx} ->
          IO.puts(
            "#{String.pad_trailing(to_string(idx), 4)} #{String.pad_trailing(to_string(jugador), 11)} #{String.pad_trailing(to_string(puntos), 10)} #{partidas}"
          )
        end)

        estado

      {:error, razon} ->
        IO.puts("Error: #{texto_error(razon)}")
        estado
    end
  end

  defp manejar_leave_game(estado) do
    if estado.partida_id do
      case GenServer.call(estado.servidor, {:leave_game, estado.partida_id, estado.usuario}) do
        :ok ->
          IO.puts("Has abandonado la partida.")

        {:error, razon} ->
          # La partida ya no existe en el servidor: se limpia igualmente el estado local
          IO.puts("Error: #{texto_error(razon)}")
      end

      %{estado | partida_id: nil}
    else
      IO.puts("No estás en ninguna partida.")
      estado
    end
  end

  defp manejar_disconnect(estado) do
    if estado.usuario do
      # Si el jugador sigue en una partida, primero la abandona
      estado = if estado.partida_id, do: manejar_leave_game(estado), else: estado

      GenServer.call(estado.servidor, {:disconnect, estado.usuario})
      IO.puts("Sesión cerrada.")
      %{estado | usuario: nil, partida_id: nil}
    else
      IO.puts("No hay sesión activa.")
      estado
    end
  end

  # PARSEO Y VALIDACIÓN DE ARGUMENTOS

  defp parse_args(args) do
    Enum.reduce(args, %{}, fn arg, acc ->
      case String.split(arg, "=", parts: 2) do
        [k, v] -> Map.put(acc, k, v)
        _ -> acc
      end
    end)
  end

  defp obtener_tema(parsed) do
    case Map.get(parsed, "tema") do
      tema when is_binary(tema) and tema != "" ->
        {:ok, tema}

      _ ->
        {:error, "Debes indicar el tema: create_game tema=<tema> preguntas=<n> tiempo=<s>"}
    end
  end

  defp obtener_entero(parsed, clave, por_defecto) do
    case Map.fetch(parsed, clave) do
      :error ->
        {:ok, por_defecto}

      {:ok, valor} ->
        case Integer.parse(valor) do
          {numero, ""} when numero > 0 -> {:ok, numero}
          _ -> {:error, "El valor de '#{clave}' debe ser un entero positivo"}
        end
    end
  end

  defp texto_error(razon) when is_binary(razon), do: razon
  defp texto_error(razon), do: inspect(razon)
end
