defmodule Trivia.Application do
  use Application

  def start(_tipo, _argumentos) do
    hijos =
      if servidor?() do
        [
          Trivia.BancoPreguntas,
          Trivia.GestorJugadores,
          Trivia.GestorPartidas,
          Trivia.SupervisorPartidas,
          Trivia.Servidor
        ]
      else
        []
      end

    Supervisor.start_link(hijos, strategy: :one_for_one, name: Trivia.Supervisor)
  end

  def servidor? do
    case System.get_env("TRIVIA_ROL") do
      "servidor" -> true
      "cliente" -> false
      _ -> Node.self() |> Atom.to_string() |> String.starts_with?("servidor")
    end
  end
end
