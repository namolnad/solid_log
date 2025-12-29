Rails.application.routes.draw do
  mount SolidLog::Service::Engine => "/"
end
