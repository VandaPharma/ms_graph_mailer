# frozen_string_literal: true

module MsGraphMailer
  class Railtie < Rails::Railtie
    # Registered as soon as the gem loads (as GitLab's microsoft_graph_mailer does), so
    # `config.action_mailer.delivery_method = :ms_graph` with
    # `config.action_mailer.ms_graph_settings = {...}` works without MsGraphMailer.configure.
    ActiveSupport.on_load(:action_mailer) do
      add_delivery_method MsGraphMailer::DELIVERY_METHOD_NAME, MsGraphMailer::Delivery
    end

    rake_tasks do
      load File.expand_path("tasks.rake", __dir__)
    end

    generators do
      require_relative "../generators/ms_graph_mailer/install/install_generator"
    end

    # Runs after config/initializers, so the application's configure block is in place.
    # Does nothing unless MsGraphMailer.configure was called.
    initializer "ms_graph_mailer.apply", after: :load_config_initializers do
      ActiveSupport.on_load(:action_mailer) { MsGraphMailer.apply!(self) if MsGraphMailer.configured? }
    end

    config.after_initialize do
      MsGraphMailer.install_job_retries! if MsGraphMailer.configured?
    end
  end
end
