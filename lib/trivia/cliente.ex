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
    entrada = IO.gets("") |> String.trim()
    partes = String.split(entrada, " ")

    nuevo_estado =
      case partes do
        ["connect", usuario, clave] ->
          case Node.ping(elem(estado.servidor, 1)) do
            :pong ->
              case GenServer.call(
                     estado.servidor,
                     {:connect, usuario, clave, estado.receptor_pid}
                   ) do
                {:ok, msg} ->
                  IO.puts(msg)
                  %{estado | usuario: usuario}

                {:error, raz} ->
                  IO.puts("Error: #{raz}")
                  estado
              end

            :pang ->
              IO.puts("Error: Servidor no disponible cuando el cliente intenta conectarse.")
              estado
          end

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

  defp manejar_create_game(args, estado) do
    if is_nil(estado.usuario) do
      IO.puts("Error: Comando ejecutado sin haber iniciado sesión.")
      estado
    else
      parsed = parse_args(args)
      tema = Map.get(parsed, "tema")
      preguntas = String.to_integer(Map.get(parsed, "preguntas", "5"))
      tiempo = String.to_integer(Map.get(parsed, "tiempo", "15"))

      case GenServer.call(
             estado.servidor,
             {:crear_partida, estado.usuario, tema, preguntas, tiempo, estado.receptor_pid}
           ) do
        {:ok, id, nivel} ->
          IO.puts(
            "Partida creada exitosamente. ID: #{id} | Nivel del creador en #{tema}: #{nivel}"
          )

          %{estado | partida_id: id}

        {:error, razon} ->
          IO.puts("Error al crear partida: #{razon}")
          estado
      end
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
          IO.puts("Error: #{razon}")
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
          IO.puts("Error al iniciar: #{razon}")
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
          IO.puts("Error: #{razon}")
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
          IO.puts("Error: #{razon}")
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
        IO.puts("Error: #{razon}")
        estado
    end
  end

  defp manejar_leave_game(estado) do
    if estado.partida_id do
      GenServer.call(estado.servidor, {:leave_game, estado.partida_id, estado.usuario})
      IO.puts("Has abandonado la partida.")
      %{estado | partida_id: nil}
    else
      IO.puts("No estás en ninguna partida.")
      estado
    end
  end

  defp manejar_disconnect(estado) do
    if estado.usuario do
      GenServer.call(estado.servidor, {:disconnect, estado.usuario})
      IO.puts("Sesión cerrada.")
      %{estado | usuario: nil, partida_id: nil}
    else
      IO.puts("No hay sesión activa.")
      estado
    end
  end

  defp parse_args(args) do
    Enum.reduce(args, %{}, fn arg, acc ->
      case String.split(arg, "=", parts: 2) do
        [k, v] -> Map.put(acc, k, v)
        _ -> acc
      end
    end)
  end
end
