require 'gitlab/oauth/user'

# LDAP extension for User model
#
# * Find or create user from omniauth.auth data
# * Links LDAP account with existing user
# * Auth LDAP user with login and password
#
module Gitlab
  module LDAP
    class User < Gitlab::OAuth::User
      class << self
        def authenticate(login, password)
          # Check user against LDAP backend if user is not authenticated
          # Only check with valid login and password to prevent anonymous bind results
          return nil unless ldap_conf.enabled && login.present? && password.present?

          ldap_user = adapter.bind_as(
            filter: user_filter(login),
            size: 1,
            password: password
          )

          find_by_uid(ldap_user.dn) if ldap_user
        end

        def adapter
          @adapter ||= OmniAuth::LDAP::Adaptor.new(ldap_conf)
        end

        def user_filter(login)
          filter = Net::LDAP::Filter.eq(adapter.uid, login)
          # Apply LDAP user filter if present
          if ldap_conf['user_filter'].present?
            user_filter = Net::LDAP::Filter.construct(ldap_conf['user_filter'])
            filter = Net::LDAP::Filter.join(filter, user_filter)
          end
          filter
        end

        def ldap_conf
          Gitlab.config.ldap
        end

        def find_by_uid(uid)
          # LDAP distinguished name is case-insensitive
          model.where("provider = ? and lower(extern_uid) = ?", provider, uid.downcase).last
        end

        def provider
          'ldap'
        end
      end

      def initialize(auth_hash)
        super
        update_user_attributes
      end

      # instance methods
      def gl_user
        @gl_user ||= find_by_uid_and_provider || find_by_email || build_new_user
      end

      def find_by_uid_and_provider
        # LDAP distinguished name is case-insensitive
        model.
          where(provider: auth_hash.provider).
          where('lower(extern_uid) = ?', auth_hash.uid.downcase).last
      end

      def find_by_email
        model.find_by(email: auth_hash.email)
      end

      def update_user_attributes
        gl_user.attributes = {
          extern_uid: auth_hash.uid,
          provider: auth_hash.provider,
          email: auth_hash.email
        }
      end

      def changed?
        gl_user.changed?
      end

      def needs_blocking?
        false
      end
    end
  end
end
