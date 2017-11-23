require 'rest-client'

# Write to Omeka using the API.
class Omelette::OmekaJsonWriter
  attr_reader :settings

  def initialize(arg_settings)
    @settings = Omelette::Importer::Settings.new arg_settings
  end

  def puts(context)
    item_id = context.omeka_item_id
    if item_id.nil?  # new item, post
      url = "#{@settings['omeka_api_root']}/items?key=#{@settings['omeka_api_key']}"
      response = RestClient.post url, context.omeka_item.to_json, { content_type: json }
    else
      url = "#{@settings['omeka_api_root']}/items/#{item_id}?key=#{@settings['omeka_api_key']}"
      response = RestClient.put url, context.omeka_item.to_json, { content_type: json }
    end
    if response.code == 200 or response.code == 201
      item_id = JSON.parse(response.body)['id']
      upload_file item_id, context
    else
      context.logger.error "POST/PUT #{context.source_item_id} failed: #{response.body}"
    end


    def upload_file(item_id, context)
      filename = context.source_item_id
      files = RestClient.get "#{api_root}/files?item=#{item_id}"
      files = JSON.parse(files.body)
      file_id = nil
      files.each do |file|
        if file['original_filename'] == File.basename(filename)
          file_id = file['id']
        end
      end
      if !file_id.nil?
        # delete the old file
        response = RestClient.delete "#{api_root}/files/#{file_id}?key=#{api_key}"
        context.logger.warn "Deleting file failed: #{file_id}: [#{response.code}] #{response.body}" unless response.code == 204
        # post a file
      end
      payload = { multipart: true, file: File.new(filename, 'rb'), data: { item: { id: item_id } }.to_json }
      response = RestClient.post "#{api_root}/files?key=#{api_key}", payload
      if response.code == 201
        context.logger.info "POSTED file: #{filename}"
      else
        context.logger.warn "POST file failed: [#{response.code}] #{filename}, #{response.code}"
      end
    end
    module_function :upload_file
  end
end