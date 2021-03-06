require 'casino/authenticator'

module CASino
  module ProcessorConcern
    module Authentication

      def validate_login_credentials(username, password)
        validate :authenticators do |authenticator_name, authenticator|
          authenticator.validate(username, password)
        end
      end

      def validate_external_credentials(params, cookies)
        validate :external_authenticators do |authenticator_name, authenticator|
          if authenticator_name == params[:external]
            authenticator.validate(params, cookies)
          end
        end
      end

      def validate(type, &validator)
        authentication_result = nil
        authenticators(type).each do |authenticator_name, authenticator|
          begin
            data = validator.call(authenticator_name, authenticator)
          rescue CASino::Authenticator::AuthenticatorError => e
            Rails.logger.error "Authenticator '#{authenticator_name}' (#{authenticator.class}) raised an error: #{e}"
          end
          if data
            authentication_result = { authenticator: authenticator_name, user_data: data }
            Rails.logger.info("Credentials for username '#{data[:username]}' successfully validated using authenticator '#{authenticator_name}' (#{authenticator.class})")
            break
          end
        end
        authentication_result
      end

      def authenticators(type)
        @authenticators ||= {}
        return @authenticators[type] if @authenticators.has_key?(type)
        @authenticators[type] = begin
          CASino.config[type].each do |name, auth|
            next unless auth.is_a?(Hash)

            authenticator = if auth[:class]
              auth[:class].constantize
            else
              load_authenticator(auth[:authenticator])
            end

            CASino.config[type][name] = authenticator.new(auth[:options])
          end
        end
      end

      private
      def load_legacy_authenticator(name)
        gemname, classname = parse_legacy_name(name)

        begin
          require gemname
          CASinoCore::Authenticator.const_get("#{classname}")
        rescue LoadError, NameError
          false
        end
      end

      def load_authenticator(name)
        legacy_authenticator = load_legacy_authenticator(name)
        return legacy_authenticator if legacy_authenticator

        gemname, classname = parse_name(name)

        begin
          require gemname
          CASino.const_get(classname)
        rescue LoadError => error
          raise LoadError, load_error_message(name, gemname, error)
        rescue NameError => error
          raise NameError, name_error_message(name, error)
        end
      end

      def parse_name(name)
        [ "casino-#{name.underscore}_authenticator", "#{name.camelize}Authenticator" ]
      end

      def parse_legacy_name(name)
        [ "casino_core-authenticator-#{name.underscore}", name.camelize ]
      end

      def load_error_message(name, gemname, error)
        "Failed to load authenticator '#{name}'. Maybe you have to include " \
        "\"gem '#{gemname}'\" in your Gemfile?\n" \
        "  Error: #{error.message}\n"
      end

      def name_error_message(name, error)
        "Failed to load authenticator '#{name}'. The authenticator class must " \
        "be defined in the CASino namespace.\n" \
        "  Error: #{error.message}\n"
      end
    end
  end
end
