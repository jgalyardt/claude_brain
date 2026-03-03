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
    num_circles = min(gen + 5, 18)

    # Main orbital circles — spread across the full viewport
    circles =
      for i <- 0..(num_circles - 1) do
        angle = i * (360 / num_circles)
        radius = 30 + rem(gen * 7 + i * 13, 50)
        cx = 960 + :math.cos(angle * :math.pi() / 180) * 340
        cy = 540 + :math.sin(angle * :math.pi() / 180) * 260
        hue = rem(hue_base + i * 25, 360)
        opacity = 0.25 + :math.sin((gen + i) * 0.5) * 0.25

        """
        <circle cx="#{Float.round(cx, 1)}" cy="#{Float.round(cy, 1)}" r="#{radius}"
          fill="hsl(#{hue}, 65%, 55%)" opacity="#{Float.round(opacity, 2)}"
          style="transform-origin: #{Float.round(cx, 1)}px #{Float.round(cy, 1)}px;">
          <animate attributeName="r" values="#{radius};#{radius + 12};#{radius}"
            dur="#{pulse_speed + i * 0.3}s" repeatCount="indefinite"/>
          <animate attributeName="opacity" values="#{Float.round(opacity, 2)};#{Float.round(min(opacity + 0.15, 0.7), 2)};#{Float.round(opacity, 2)}"
            dur="#{pulse_speed + i * 0.5}s" repeatCount="indefinite"/>
        </circle>
        """
      end

    # Ambient floating blobs for depth
    blobs =
      for i <- 0..5 do
        bx = rem(gen * 131 + i * 317, 1920)
        by = rem(gen * 97 + i * 251, 1080)
        br = 80 + rem(i * 47, 60)
        bh = rem(hue_base + i * 60, 360)

        """
        <circle cx="#{bx}" cy="#{by}" r="#{br}"
          fill="hsl(#{bh}, 50%, 40%)" opacity="0.08" filter="url(#evo-blur)">
          <animate attributeName="cx" values="#{bx};#{bx + 40};#{bx}"
            dur="#{8 + i * 2}s" repeatCount="indefinite"/>
          <animate attributeName="cy" values="#{by};#{by - 30};#{by}"
            dur="#{10 + i * 1.5}s" repeatCount="indefinite"/>
        </circle>
        """
      end

    """
    <svg viewBox="0 0 1920 1080" style="width: 100%; height: 100%;"
      preserveAspectRatio="xMidYMid slice">
      <defs>
        <radialGradient id="evo-glow" cx="50%" cy="50%" r="50%">
          <stop offset="0%" stop-color="hsl(#{hue_base}, 80%, 65%)" stop-opacity="0.3"/>
          <stop offset="60%" stop-color="hsl(#{hue_base}, 60%, 30%)" stop-opacity="0.1"/>
          <stop offset="100%" stop-color="transparent" stop-opacity="0"/>
        </radialGradient>
        <radialGradient id="evo-bg" cx="50%" cy="40%" r="70%">
          <stop offset="0%" stop-color="#2d2520" stop-opacity="1"/>
          <stop offset="100%" stop-color="#1a1714" stop-opacity="1"/>
        </radialGradient>
        <filter id="evo-blur">
          <feGaussianBlur stdDeviation="40"/>
        </filter>
      </defs>
      <rect width="1920" height="1080" fill="url(#evo-bg)"/>
      #{Enum.join(blobs, "\n")}
      <circle cx="960" cy="540" r="280" fill="url(#evo-glow)"/>
      #{Enum.join(circles, "\n")}
      <text x="960" y="555" text-anchor="middle" fill="white" font-size="64"
        font-family="monospace" font-weight="bold" opacity="0.15">
        GEN #{gen}
      </text>
    </svg>
    """
  end
end
