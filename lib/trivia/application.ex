defmodule Trivia.Application do
  use Application

  def start(_tipo, _argumentos) do
    hijos = [
      Trivia.GestorJugadores,
      Trivia.BancoPreguntas,
      Trivia.GestorPartidas,
      Trivia.SupervisorPartidas,
      Trivia.Servidor
    ]

    opciones = [
      strategy: :rest_for_one,
      name: Trivia.Supervisor
    ]

    Supervisor.start_link(hijos, opciones)
  end
end
