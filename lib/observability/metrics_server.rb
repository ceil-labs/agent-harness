# frozen_string_literal: true

require "async"
require "async/http/endpoint"
require "falcon/server"
require "falcon/service/supervised"

module AgentHarness
  # HTTP server for exposing Prometheus metrics endpoint
  # Runs on port 9090 by default
  class MetricsServer
    DEFAULT_PORT = 9090
    DEFAULT_HOST = "0.0.0.0"

    attr_reader :port, :host, :metrics

    # @param metrics [Metrics] Metrics collector instance
    # @param port [Integer] Port to listen on
    # @param host [String] Host to bind to
    def initialize(metrics:, port: DEFAULT_PORT, host: DEFAULT_HOST)
      @metrics = metrics
      @port = port
      @host = host
      @endpoint = nil
      @server = nil
    end

    # Start the metrics server
    # Blocks until stop() is called
    # @return [void]
    def start
      Async do
        @endpoint = Async::HTTP::Endpoint.parse("http://#{@host}:#{@port}")

        app = build_app
        @server = Falcon::Server.new(app, @endpoint)

        # Log startup if logger is available
        puts({
          timestamp: Time.now.utc.iso8601,
          level: "info",
          event: "metrics_server.started",
          context: { host: @host, port: @port }
        }.to_json)

        @server.run
      end
    end

    # Stop the metrics server
    # @return [void]
    def stop
      @server&.stop
    end

    private

    def build_app
      ->(env) {
        request = Rack::Request.new(env)

        case request.path_info
        when "/metrics"
          handle_metrics
        when "/health"
          handle_health
        else
          [404, { "content-type" => "text/plain" }, ["Not Found"]]
        end
      }
    end

    def handle_metrics
      body = @metrics.exposition_format

      [200, { "content-type" => "text/plain; version=0.0.4" }, [body]]
    rescue => e
      [500, { "content-type" => "text/plain" }, ["Error generating metrics: #{e.message}"]]
    end

    def handle_health
      [200, { "content-type" => "application/json" }, [{ status: "healthy" }.to_json]]
    end
  end
end
