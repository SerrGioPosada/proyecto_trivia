defmodule Trivia.Application do
  use Application

  def start(_tipo, _argumentos) do
    hijos = [
      Trivia.BancoPreguntas,
      Trivia.GestorPartidas,
      Trivia.Servidor
    ]

    opciones = [
      strategy: :one_for_one,
      name: Trivia.Supervisor
    ]

    Supervisor.start_link(hijos, opciones)
  end
end
