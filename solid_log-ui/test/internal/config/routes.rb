Rails.application.routes.draw do
  mount SolidLog::UI::Engine, at: "/logs"
end
