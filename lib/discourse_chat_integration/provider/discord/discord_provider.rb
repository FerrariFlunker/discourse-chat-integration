# frozen_string_literal: true
require "date"

module DiscourseChatIntegration
  module Provider
    module DiscordProvider
      PROVIDER_NAME = "discord".freeze
      PROVIDER_ENABLED_SETTING = :chat_integration_discord_enabled

      CHANNEL_PARAMETERS = [
        { key: "name", regex: '^\S+' },
        { key: "webhook_url", regex: '^https:\/\/discord(?:app)?\.com\/api\/webhooks\/', unique: true, hidden: true }
      ].freeze

      def self.send_message(url, message)
        http = Net::HTTP.new("discordapp.com", 443)
        http.use_ssl = true

        uri = URI(url)

        req = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json')
        req.body = message.to_json
        response = http.request(req)

        response
      end

      def self.ensure_protocol(url)
        return url if !url.start_with?('//')
        "http:#{url}"
      end

      def self.generate_discord_message(post, rule=nil)

        display_name = "@#{post.user.username}"
        full_name = post.user.name || ""

        if !(full_name.strip.empty?) && (full_name.strip.gsub(' ', '_').casecmp(post.user.username) != 0) && (full_name.strip.gsub(' ', '').casecmp(post.user.username) != 0)
          display_name = "#{full_name} @#{post.user.username}"
        end

        topic = post.topic

        category = ''
        if topic.category
          category = (topic.category.parent_category) ? "#{topic.category.parent_category.name}/#{topic.category.name}" : "#{topic.category.name}"
        end

        prefix_message = ''
        if rule 
          prefix_message = build_prefix_message(post, rule)
        end

        message = {
          content: prefix_message,
          embeds: [{
            title: topic.title,
            color: topic.category ? topic.category.color.to_i(16) : nil,
            description: post.excerpt(SiteSetting.chat_integration_discord_excerpt_length, text_entities: true, strip_links: true, remap_emoji: true),
            url: post.full_url,
            author: {
              name: display_name,
              url: Discourse.base_url + "/u/" + post.user.username,
              icon_url: ensure_protocol(post.user.small_avatar_url)
            },
            timestamp: DateTime.now.strftime('%m/%d/%Y')
          }]
        }

        message
      end

      def self.build_prefix_message(post, rule)
        msg_fields = {'{username}' => post.user.username, '{title}' =>  post.topic.title, "{category}" => post.topic.category.name}
        if post.is_first_post? && rule.new_topic_prefix
          return rule.new_topic_prefix.gsub(/{(.*?)}/, msg_fields)
        elsif !post.is_first_post? && rule.new_reply_prefix
          return rule.new_reply_prefix.gsub(/{(.*?)}/, msg_fields)
        else
          return ""
        end
      end     

      def self.trigger_notification(post, channel, rule)
        # Adding ?wait=true means that we actually get a success/failure response, rather than returning asynchronously
        webhook_url = "#{channel.data['webhook_url']}?wait=true"
        message = generate_discord_message(post, rule)
        response = send_message(webhook_url, message)

        if !response.kind_of?(Net::HTTPSuccess)
          raise ::DiscourseChatIntegration::ProviderError.new(info: {
            error_key: nil, message: message, response_body: response.body
          })
        end
      end

    end
  end
end
