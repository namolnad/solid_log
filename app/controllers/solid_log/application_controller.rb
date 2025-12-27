module SolidLog
  class ApplicationController < ActionController::Base
    include Turbo::Streams::TurboStreamsTagBuilder
    helper Turbo::Engine.helpers
    helper Importmap::ImportmapTagsHelper

    # Logging is silenced by SolidLog::SilenceMiddleware
  end
end
