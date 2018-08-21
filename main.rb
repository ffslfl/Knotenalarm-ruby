require 'httparty'
require 'time'
require 'yaml'
require 'matrix_sdk'
# require 'rufus-scheduler'

# Main Class
class Main
  include HTTParty
  def start
    config_url = config['config_url']
    response = self.class.get(config_url)
    parsed_response = response.parsed_response
    parsed_response['dataPath'].each do |data_path|
      puts "#{Time.now.strftime('%d. %h %G | %T')} - URL: #{data_path}"
      nodelist "#{data_path}/nodelist.json"
    end
  end

  def prepare_matrix
    if config['Matrix']['homeserver'] != '' &&
       config['Matrix']['mxid'] != '' &&
       config['Matrix']['passwd'] != ''
      hs_url = config['Matrix']['homeserver']
      client = MatrixSdk::Client.new hs_url
      puts "#{Time.now.strftime('%d. %h %G | %T')} - Logging in on Matrix..."
      begin
        client.login(config['Matrix']['mxid'],
                     config['Matrix']['passwd'],
                     allow_sync_retry: 15)
      rescue Net::HTTPGatewayTimeOut
        @matrix_error = false
        puts "#{Time.now.strftime('%d. %h %G | %T')} -  happened on sync"
      rescue => e
        @matrix_error = true
        puts "#{Time.now.strftime('%d. %h %G | %T')} - Some error happened: #{e}"
      end
      unless @matrix_error
        room_alias = config['Matrix']['room']
        @room = client.find_room(room_alias)
        @room ||= begin
          puts "#{Time.now.strftime('%d. %h %G | %T')} - Joining room..."
          @client.join_room(room_alias)
        end

        puts "#{Time.now.strftime('%d. %h %G | %T')} - Logged in on Matrix and joined room..."
      end
    end
  end

  # @return [Object]
  def config
    YAML.load_file('config.yml')
  end

  # @param [Object] url
  def nodelist(url)
    nodelist_resp = self.class.get(url)
    parsed_nodelist = nodelist_resp.parsed_response
    parsed_nodelist['nodes'].each { |node| work(node) }
  end

  # @param [Object] node_data
  def work(node_data)
    if node_data.key?('status') &&
       node_data['status'].key?('firstcontact')
      t = Time.parse node_data['status']['firstcontact']
      if t > Time.now &&
         node_data.key?('position') &&
         node_data['position'].key?('lat') &&
         node_data['position']['lat'] != 0
        get_location(node_data['position'], node_data)
      else
        puts "#{Time.now.strftime('%d. %h %G | %T')} - Node not new"
      end
    else
      puts "#{Time.now.strftime('%d. %h %G | %T')} - Firstcontact empty: #{node_data}"
    end
  end

  def get_location(position, node_data)
    json_url = 'https://nominatim.openstreetmap.org/reverse?format=json'\
                "&lat=#{position['lat']}"\
                "&lon=#{position['long']}"\
                '&zoom=16&addressdetails=1'
    resp = self.class.get(json_url).parsed_response

    name = location_name resp

    send_matrix(name, node_data) if config.key?('Matrix') && !@matrix_error
  end

  # @param [Object] resp
  # @return [String]
  def location_name(resp)
    if resp.key?('address') && resp['address'].key?('village')
      resp['address']['village']
    elsif resp.key?('address') && resp['address'].key?('town')
      resp['address']['town']
    elsif resp.key?('address') && resp['address'].key?('city')
      resp['address']['city']
    else
      'unbekannt'
    end
  end

  # @param [Object] location
  # @param [Object] node_data
  def send_matrix(location, node_data)
    new_node_msg = "In #{location} gibt es einen neuen #Freifunk-Knoten:"\
                    " #{node_data['name']} #{config['map_url']}"\
                    "#!v:m;n:#{node_data['id']}"
    @room.send_notice new_node_msg
  end
end

# scheduler = Rufus::Scheduler.new
main = Main.new
main.prepare_matrix if main.config.key?('Matrix')
# scheduler.every '10m' do
#   main.start
# end

loop do
  main.start
  sleep 10 * 60
end
