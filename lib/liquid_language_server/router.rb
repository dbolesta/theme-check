# frozen_string_literal: true
require "theme_check"

module LiquidLanguageServer
  class OffenseFactory
    def initialize
      @config = nil
    end

    def load_config(file_path)
      if @config.nil?
        # Try to find the root folder
        config_path = ThemeCheck::Config.find(file_path) || ThemeCheck::Config.find(file_path, ".git") || file_path
        @config = ThemeCheck::Config.from_path(config_path)
      end
      @config
    end

    def offenses(file_path)
      config = load_config(file_path)

      theme = ThemeCheck::Theme.new(config.root)

      if theme.all.empty?
        return []
      end

      analyzer = ThemeCheck::Analyzer.new(theme, config.enabled_checks)
      analyzer.analyze_file(file_path)
    end
  end

  class Router
    def initialize(offense_factory = OffenseFactory.new)
      @offense_factory = offense_factory
    end

    def on_initialize(id, _params)
      {
        type: "response",
        id: id,
        result: {
          capabilities: {
            textDocumentSync: {
              openClose: true,
              change: false,
              willSave: false,
              save: true,
            },
          },
        },
      }
    end

    def on_initialized(_id, _params)
      {
        type: "log",
        message: "initialized!",
      }
    end

    def on_shutdown(_id, _params)
      {
        type: 'log',
        message: 'shutting down',
      }
    end

    def on_exit(_id, _params)
      {
        type: "exit",
      }
    end

    def on_text_document_did_close(_id, params)
      {
        type: "log",
        message: "Document closed. #{params['textDocument']['uri']}",
      }
    end

    def on_text_document_did_change(_id, params)
      {
        type: "log",
        message: "Did change sent. #{params['textDocument']['uri']}",
      }
    end

    def on_text_document_did_open(_id, params)
      prepare_diagnostics_for_params(params)
    end

    def on_text_document_did_save(_id, params)
      prepare_diagnostics_for_params(params)
    end

    private

    def prepare_diagnostics_for_params(params)
      text_document = params['textDocument']
      uri = text_document['uri']
      prepare_diagnostics(uri)
    end

    def prepare_diagnostics(uri)
      {
        type: "notification",
        method: 'textDocument/publishDiagnostics',
        params: {
          uri: uri,
          diagnostics: offenses(uri).map { |offense| offense_to_diagnostic(offense) },
        },
      }
    end

    def offenses(uri)
      @offense_factory.offenses(uri.sub('file://', ''))
    end

    def offense_to_diagnostic(offense)
      {
        range: range(offense),
        severity: severity(offense),
        code: offense.code_name,
        source: "theme-check",
        message: offense.message,
      }
    end

    def severity(offense)
      case offense.severity
      when :error
        1
      when :suggestion
        2
      when :style
        3
      else
        4
      end
    end

    def range(offense)
      {
        start: {
          line: offense.start_line,
          character: offense.start_column,
        },
        end: {
          line: offense.end_line,
          character: offense.end_column,
        },
      }
    end
  end
end
