defmodule Evo.Evolvable.CreativeDisplay do
  @moduledoc """
  Generates creative HTML/SVG visualizations for the evolution dashboard.
  This module is part of the evolvable surface — the system can modify it.

  Returns raw HTML strings rendered on the dashboard via Phoenix.HTML.raw/1.
  Claude can evolve this module to produce any visual output it wants:
  SVG generative art, CSS animations, data visualizations, ASCII art, etc.
  """

  @doc """
  Renders a creative visualization based on current evolution stats.

  Accepts a map with keys like :generation, :accept_rate, :budget_used, etc.
  Returns an HTML string (may include inline SVG, CSS, animations).
  """
  @spec render(map()) :: String.t()
  def render(stats) do
    gen = Map.get(stats, :generation, 0)
    rate = Map.get(stats, :accept_rate, 0)
    budget = Map.get(stats, :budget_used, 0)

    hue_base = rem(gen * 37, 360)
    pulse_speed = max(0.5, 3.0 - rate / 30.0)
    num_circles = min(gen + 3, 12)

    circles =
      for i <- 0..(num_circles - 1) do
        angle = i * (360 / num_circles)
        radius = 20 + rem(gen * 7 + i * 13, 30)
        cx = 150 + :math.cos(angle * :math.pi() / 180) * 60
        cy = 100 + :math.sin(angle * :math.pi() / 180) * 50
        hue = rem(hue_base + i * 30, 360)
        opacity = 0.3 + :math.sin((gen + i) * 0.5) * 0.3

        """
        <circle cx="#{Float.round(cx, 1)}" cy="#{Float.round(cy, 1)}" r="#{radius}"
          fill="hsl(#{hue}, 70%, 60%)" opacity="#{Float.round(opacity, 2)}"
          style="animation: pulse#{i} #{pulse_speed}s ease-in-out infinite alternate;
                 transform-origin: #{Float.round(cx, 1)}px #{Float.round(cy, 1)}px;">
          <animate attributeName="r" values="#{radius};#{radius + 8};#{radius}"
            dur="#{pulse_speed + i * 0.2}s" repeatCount="indefinite"/>
        </circle>
        """
      end

    bar_width = min(budget, 100) * 2.5
    bar_hue = if budget > 80, do: 0, else: 120 - budget

    """
    <div style="background: linear-gradient(135deg, #0f0c29, #302b63, #24243e);
                border-radius: 12px; padding: 24px; position: relative; overflow: hidden;">
      <svg viewBox="0 0 300 200" style="width: 100%; max-height: 200px;">
        <defs>
          <radialGradient id="evo-glow">
            <stop offset="0%" stop-color="hsl(#{hue_base}, 80%, 70%)" stop-opacity="0.4"/>
            <stop offset="100%" stop-color="transparent"/>
          </radialGradient>
        </defs>
        <circle cx="150" cy="100" r="80" fill="url(#evo-glow)"/>
        #{Enum.join(circles, "\n")}
        <text x="150" y="105" text-anchor="middle" fill="white" font-size="28"
          font-family="monospace" font-weight="bold" opacity="0.9">
          GEN #{gen}
        </text>
        <rect x="25" y="175" width="#{bar_width}" height="8" rx="4"
          fill="hsl(#{bar_hue}, 70%, 55%)" opacity="0.7"/>
        <text x="25" y="170" fill="rgba(255,255,255,0.5)" font-size="8" font-family="monospace">
          budget #{budget}%
        </text>
        <text x="275" y="170" text-anchor="end" fill="rgba(255,255,255,0.5)"
          font-size="8" font-family="monospace">
          accept #{rate}%
        </text>
      </svg>
      <style>
        @keyframes evo-spin {
          from { transform: rotate(0deg); }
          to { transform: rotate(360deg); }
        }
      </style>
    </div>
    """
  end
end
