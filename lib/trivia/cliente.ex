defmodule Trivia.Cliente do
  @moduledoc """
  Consola del jugador. No tiene lógica de juego: traduce lo que se escribe en
  peticiones al servidor y muestra lo que llega (las notificaciones las imprime
  el Receptor, que es otro proceso).

      iex --sname pedro -S mix
      iex> Trivia.Cliente.iniciar_cliente()                 # servidor@<este host>
      iex> Trivia.Cliente.iniciar_cliente(:"servidor@host") # servidor en otro host
  """

  @servidor_nombre Trivia.Servidor

  def nodo_por_defecto do
    {:ok, host} = :inet.gethostname()
    :"servidor@#{host}"
  end

  def iniciar_cliente(nodo_servidor \\ nodo_por_defecto()) do
    Node.connect(nodo_servidor)
    {:ok, receptor_pid} = Trivia.Receptor.start_link([])

    IO.puts("=== CLIENTE DE TRIVIA ===")
    IO.puts("Escribe help para ver los comandos.")

    bucle_comandos(%{
      usuario: nil,
      partida_id: nil,
      receptor_pid: receptor_pid,
      servidor: {@servidor_nombre, nodo_servidor}
    })

    GenServer.stop(receptor_pid)
    IO.puts("Cliente cerrado.")
  end

  defp bucle_comandos(estado) do
    IO.write("\nComando > ")

    case IO.gets("") do
      :eof ->
        salir(estado)

      {:error, _} ->
        salir(estado)

      entrada ->
        case ejecutar(String.split(entrada), estado) do
          :salir -> :ok
          nuevo_estado -> bucle_comandos(nuevo_estado)
        end
    end
  end

  defp salir(estado) do
    if estado.usuario, do: llamar(estado, {:disconnect, estado.usuario})
    :ok
  end

  # COMANDOS

  defp ejecutar([], estado), do: estado

  defp ejecutar(["help"], estado) do
    IO.puts("""
    connect <usuario> <clave>              disconnect
    create_game tema=<t> preguntas=<n> tiempo=<s>
    add_bot <facil|dificil>                start_game
    answer <A|B|C|D>                       leave_game
    score                                  ranking [tema]
    exit
    """)

    estado
  end

  defp ejecutar(["connect", usuario, clave], estado) do
    usuario = usuario |> String.trim() |> String.downcase()

    case Node.ping(elem(estado.servidor, 1)) do
      :pong ->
        case llamar(estado, {:connect, usuario, clave, estado.receptor_pid}) do
          {:ok, msg} ->
            IO.puts(msg)
            %{estado | usuario: usuario}

          {:error, razon} ->
            IO.puts("Error: #{texto_error(razon)}")
            estado
        end

      :pang ->
        IO.puts("Error: Servidor no disponible. Verifica que el nodo servidor esté corriendo.")
        estado
    end
  end

  defp ejecutar(["create_game" | args], estado) do
    con_sesion(estado, fn ->
      parsed = parse_args(args)

      with tema when is_binary(tema) <- Map.get(parsed, "tema"),
           {:ok, preguntas} <- entero(Map.get(parsed, "preguntas", "5"), "preguntas"),
           {:ok, tiempo} <- entero(Map.get(parsed, "tiempo", "15"), "tiempo") do
        peticion = {:crear_partida, estado.usuario, tema, preguntas, tiempo, estado.receptor_pid}

        case llamar(estado, peticion) do
          {:ok, id, nivel} ->
            IO.puts("Partida creada. ID: #{id} | Nivel de #{estado.usuario} en #{tema}: #{nivel}")
            %{estado | partida_id: id}

          {:error, razon} ->
            IO.puts("Error al crear partida: #{texto_error(razon)}")
            estado
        end
      else
        nil ->
          IO.puts("Uso: create_game tema=<tema> preguntas=<n> tiempo=<segundos>")
          estado

        {:error, mensaje} ->
          IO.puts("Error: #{mensaje}")
          estado
      end
    end)
  end

  defp ejecutar(["add_bot", dificultad], estado) do
    con_partida(estado, "add_bot", fn ->
      case llamar(estado, {:add_bot, estado.partida_id, dificultad}) do
        {:ok, nombre_bot} ->
          IO.puts("Bot agregado: #{nombre_bot}")
          estado

        {:error, razon} ->
          mostrar_error(razon, estado)
      end
    end)
  end

  defp ejecutar(["start_game"], estado) do
    con_partida(estado, "start_game", fn ->
      case llamar(estado, {:start_game, estado.partida_id}) do
        {:ok, _partida} ->
          IO.puts("¡Partida iniciada!")
          estado

        {:error, razon} ->
          mostrar_error(razon, estado)
      end
    end)
  end

  defp ejecutar(["answer", letra], estado) do
    con_partida(estado, "answer", fn ->
      case llamar(estado, {:responder, estado.partida_id, estado.usuario, letra}) do
        {:ok, :respuesta_registrada} ->
          IO.puts("Respuesta registrada.")
          estado

        {:error, razon} ->
          mostrar_error(razon, estado)
      end
    end)
  end

  defp ejecutar(["score"], estado) do
    con_sesion(estado, fn ->
      case llamar(estado, {:score, estado.usuario}) do
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
    end)
  end

  defp ejecutar(["ranking" | args], estado) do
    con_sesion(estado, fn ->
      tema = List.first(args)

      case llamar(estado, {:ranking, tema}) do
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
    end)
  end

  defp ejecutar(["leave_game"], estado) do
    if estado.partida_id do
      llamar(estado, {:leave_game, estado.partida_id, estado.usuario})
      IO.puts("Has abandonado la partida.")
      %{estado | partida_id: nil}
    else
      IO.puts("No estás en ninguna partida.")
      estado
    end
  end

  defp ejecutar(["disconnect"], estado) do
    if estado.usuario do
      llamar(estado, {:disconnect, estado.usuario})
      IO.puts("Sesión cerrada.")
      %{estado | usuario: nil, partida_id: nil}
    else
      IO.puts("No hay sesión activa.")
      estado
    end
  end

  defp ejecutar(["exit"], estado) do
    salir(estado)
    :salir
  end

  defp ejecutar(_otro, estado) do
    IO.puts("Comando desconocido o sintaxis incorrecta. Escribe help.")
    estado
  end

  # AUXILIARES

  # Petición al servidor que nunca tumba el cliente si el servidor no responde.
  defp llamar(estado, peticion) do
    GenServer.call(estado.servidor, peticion, 15_000)
  catch
    :exit, _ -> {:error, "Servidor no disponible"}
  end

  defp con_sesion(estado, fun) do
    if is_nil(estado.usuario) do
      IO.puts("Error: Comando ejecutado sin haber iniciado sesión (usa connect).")
      estado
    else
      fun.()
    end
  end

  defp con_partida(estado, comando, fun) do
    cond do
      is_nil(estado.usuario) ->
        IO.puts("Error: Comando ejecutado sin haber iniciado sesión (usa connect).")
        estado

      is_nil(estado.partida_id) ->
        IO.puts("Error: #{comando} ejecutado sin estar en una partida.")
        estado

      true ->
        fun.()
    end
  end

  # Si la partida ya no existe en el servidor (terminó o se canceló), se libera al cliente.
  defp mostrar_error(razon, estado) do
    texto = texto_error(razon)
    IO.puts("Error: #{texto}")

    if texto in ["La partida no existe", "La partida no está disponible"] do
      %{estado | partida_id: nil}
    else
      estado
    end
  end

  defp texto_error(razon) when is_binary(razon), do: razon
  defp texto_error(razon), do: inspect(razon)

  defp entero(texto, nombre) do
    case Integer.parse(texto) do
      {n, ""} when n > 0 -> {:ok, n}
      _ -> {:error, "#{nombre} debe ser un entero positivo"}
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
