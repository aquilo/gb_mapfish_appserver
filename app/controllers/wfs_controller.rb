require 'net/http.rb'
require 'uri'

class WfsController < ApplicationController

  def show
    logger.info "----> WMS call with user '#{current_user.try(:login)}'"

    #Send redirect for public services
    #if public?(params[:service], host_zone(request.host))
    #  url, path = mapserv_request_url(request)
    #  expires_in 2.minutes, :public => true
    #  redirect_to "#{url.scheme}://#{url.host}#{path}"
    #  return
    #end

    topic = Topic.where(:name => params[:service]).first
    topic_accessible = topic && can?(:show, topic)
    wfs_accessible = can?(:show, Wfs.new(params[:service]))
    if !topic_accessible && !wfs_accessible
      logger.info "----> Topic/WFS '#{params[:service]}' not accessible with roles #{current_roles.roles.collect(&:name).join('+')}!"
      log_user_permissions(:show, topic) if topic
      log_user_permissions(:show, Wfs.new(params[:service]))
      request_http_basic_authentication('Secure WFS Login')
      return
    end
    call_wfs(request)
  end

  private

  def mapserv_base_url(request)
    server = MAPSERV_SERVER || "#{request.protocol}#{request.host}"
    "#{server}#{MAPSERV_URL}?MAP=#{MAPPATH}/#{@zone}/#{params[:service]}.map"
  end

  def mapserv_request_url(request)
    wfs_url = mapserv_base_url(request)
    url = URI.parse(URI.decode(wfs_url))
    if url.host.nil?
      url = URI.parse(URI.decode("#{request.protocol}#{wfs_url}"))
    end
    if url.host.nil?
      url = URI.parse(URI.decode("#{request.protocol}#{request.host}#{wfs_url}"))
    end

    path = "#{url.path}?"
    path << url.query << '&' if url.query
    path << request.query_string
    [url, path]
  end

  def call_wfs(request)
    url, path = mapserv_request_url(request)
    logger.info "Forward request: #{url.scheme}://#{url.host}#{path}"

#    if request.get? then
#      result = Net::HTTP.get_response(url.host, path, url.port)
#      send_data result.body, :status => result.code, :type => result.content_type, :disposition => 'inline'
#    else
#      render :nothing => true
#    end
    response = nil
    begin
      http = Net::HTTP.new(url.host, url.port)
      http.start do
        case request.method.to_s
        when 'GET'  then response = http.get(path) #, request.headers
        when 'POST' then response = http.post(path, request.body.read, {'Content-Type' => 'application/xml'}) #, request.headers)
        else
          raise Exception.new("unsupported method `#{request.method}'.")
        end
      end
    rescue => err
      logger.info("#{err.class}: #{err.message}")
      render :nothing => true
      return
    end
    send_data response.body, :status => response.code, :type => response.content_type, :disposition => 'inline'
  end

  #Public accessible WFS
  #REMARK: permission change needs restart!
  def public?(name, zone)
    @@accessible ||= {}
    @@accessible[zone] ||= {}
    @@accessible[zone][name] ||= begin
      test_ability = Ability.new(Ability::Roles.new(nil, zone)) # additional param for request origin?
      test_ability.can?(:show, Wfs.new(name))
    end
  end


end
