#!/usr/bin/env ruby -wKU
#encoding utf-8

require 'rubygems'
require 'optparse'
require 'mechanize'
require 'json'

def keyfy_str(str)
  str.encode!("UTF-8")
  dc = str.downcase.strip
  dc = dc.index(" ") ? dc.split(" ").join("_") : dc
  dc = dc.index(".") ? dc.split(".").join : dc
  dc
end

class CNEQueryString
  attr_accessor :state, :municipality, :parish, :center, :table
  
  def initialize(options={})
    @state = "00"
    @municipality = "00"
    @parish = "00"
    @center = "00"
    @table = "00"

    options.each {|k, v| self.send("#{k}=".to_sym, v) }
  end
  
  def update_attributes(attrs)
    reset_attributes
    attrs.each {|k, v| self.send("#{k.to_s}=".to_sym, v) }
  end
  
  def reset_attributes
    [:state, :municipality, :parish, :center, :table].each do |k|
      self.send("#{k.to_s}=".to_sym, 0)
    end
  end
  
  def build()
    "?e=#{@state}&m=#{@municipality}&p=#{@parish}&c=#{@center}&t=#{@table}&ca=00&v=02"
  end
  
  def parse(str=nil)
    results = {}
    regex = /e=(\d+)+&m=(\d+)&p=(\d+)&c=(\d+)&t=(\d+)/
    
    str = build unless str
    
    matchdata = str.match(regex)
    if(matchdata)
      captures = matchdata.captures
      [:state, :municipality, :parish, :center, :table].each_with_index { |key, index| results[key] = captures[index] if(captures[index] != "00") }
    end
    results
  end
end

class Parser
  BASE_URL = "http://www.cne.gob.ve/divulgacion_parlamentarias_2010/index.php"
  ENTITIES = [:state, :municipality, :parish, :center, :table]
  VOTE_TYPE_TO_ID = {
    :parlatino => "parlamento_latinoamericano_lista",
    :parlatino_indigena => "parlamento_latinoamericano_indigena", 
    :asamblea_lista => "asamblea_nacional_lista", 
    :asamblea_nominal => "asamblea_nacional_nominal", 
    :asamblea_indigena => "asamblea_nacional_indigena"
  }
  
  def initialize(args)
    @options = {:query => {}}
    opts = OptionParser.new do |opts|
      opts.banner = "Usage: parser.rb [options]"
      
      opts.separator ""
      opts.separator "Specific Options:"
      
      opts.on("-s", "--state NUMBER", "Specify the state to parse") do |state|
        @options[:query][:state] = state
      end
      
      opts.on("-m", "--municipality NUMBER", "Specify the municipality to parse") do |muni|
        @options[:query][:municipality] = muni
      end
      
      opts.on("-p", "--parish NUMBER", "Specify the parish to parse") do |parish|
        @options[:query][:parish] = parish
      end
      
      opts.on("-c", "--center NUMBER", "Specify the voting_center to parse") do |voting_center|
        @options[:query][:center] = voting_center
      end
      
      opts.on("-t", "--table NUMBER", "Specify the voting_table to parse") do |voting_table|
        @options[:query][:table] = voting_table
      end
      
      opts.on("-i", "--ignore comma-separated NUMBERS", "Specify the administrative entities children of the last specified admin-level to ignore") do |ignores|
        @options[:ignore_list] = ignores.split(",")
      end
      
      opts.separator ""
      opts.separator "Common options:"

      # No argument, shows at tail.  This will print an options summary.
      # Try it and see!
      opts.on_tail("-h", "--help", "Show this message") do
        puts opts
        exit
      end
    end
    
    
    opts.parse!(args)

    @query_string = CNEQueryString.new(@options[:query])
    @mechanizer = Mechanize.new()
    
    if(@options.has_key?(:ignore_list))
      @options[:ignore_type] = ENTITIES[@query_string.parse.keys.length]
      puts "ignore list: #{@options[:ignore_list]}"
      puts "ignore type: #{@options[:ignore_type]}"
    end
    
  end
  
  def parse(admin)
    page = @mechanizer.get(BASE_URL + @query_string.build)
    links = admin_entities_from_navigation_panel(page)
    
    if(links.length == 0)
      VOTE_TYPE_TO_ID.keys.each do |vote_type|
        admin[:results][vote_type] = results_from_table(page, vote_type)
      end
      return admin
    else
      data = nil
      links.each do |link|
        type = ENTITIES[link[:breadcrumbs].keys.length - 1]
        
        if(@options.has_key?(:ignore_list) &&  @options[:ignore_type] == type)
          next if @options[:ignore_list].include?(link[:breadcrumbs][type])
        end
        
        admin_ent = { :name => link[:name], :type => type }
        
        if(type == :table)
          admin_ent[:name] = "mesa_" + admin_ent[:name].match(/(\d+)/)[1]
        end
        
        if(type != :table)
          admin_ent[:subentities] = []
        else
          admin_ent[:results] = {}
        end
        
        admin.push(admin_ent)

        @query_string.update_attributes(link[:breadcrumbs])
        puts "#{'  '*ENTITIES.index(type)}Parsing #{type} #{link[:breadcrumbs][type]}"
        #sleep(1)
      
        if(type != :table)
          data = parse(admin_ent[:subentities])
        else
          data = parse(admin_ent)
        end
        
        if(type == :parish)
          puts "#{'  '*ENTITIES.index(type)}Writing data for parish_#{admin_ent[:name]}_#{link[:breadcrumbs][type]}"
          f = File.new("parroquia_#{link[:breadcrumbs][:state]}#{link[:breadcrumbs][:municipality]}#{link[:breadcrumbs][:parish]}.json", "w")
          f << admin_ent.to_json
          f.close
        end
        
        data
      end
    end
  end
  
  private
  
  def results_from_table(page, vote_type)
    results = {}
    results[:alliances] = []
    
    comments = page.search("##{VOTE_TYPE_TO_ID[vote_type]}").search("comment()")
    
    comments.each do |comment|
      #previous element holds the name of the alliance
      #next element holds the div with the collapsible info
      alliance_votes = comment.previous_element.search("td:nth-child(4)").text.strip.to_i
      if(alliance_votes > 0)
        res = {}
        
        if([:parlatino_indigena, :asamblea_nominal, :asamblea_indigena].include?(vote_type))
          res[:candidate] = keyfy_str(comment.previous_element.search("td:nth-child(1)").first.children.first.text)
        end
        
        res[:name] = keyfy_str(comment.previous_element.search("td:nth-child(2) b").text)
        res[:votes] = alliance_votes
        
        res[:details] = extract_alliance_details(comment, vote_type)

        results[:alliances].push(res)
      end
    end

    #if there are no comments then there's the funny error message
    if comments.length > 0
      if(vote_type == :asamblea_nominal)
        results[:circunscription] = page.search("##{VOTE_TYPE_TO_ID[vote_type]}").search("table:first td:nth-child(2)").text.strip.to_i
      end
    
      if(vote_type == :asamblea_indigena)
        results[:region] = keyfy_str(page.search("##{VOTE_TYPE_TO_ID[vote_type]}").search("table:first td:nth-child(2)").children.first.text)
      end
    
      details_table = details_table_for_vote_type(vote_type, page)
    
      #tecnical data for vote_type
      if(vote_type != :asamblea_indigena)
        extract_tecnical_data(results, details_table)
      end
    else
      results = {:unavailable => true}
    end

    results
  end
  
  def extract_alliance_details(comment, vote_type)
    res = []
    alliance_details_table = comment.next_element.search("div table:last")

    if(![:parlatino_indigena, :asamblea_indigena].include?(vote_type))
      data_rows = alliance_details_table.search("tr:nth-child(2n)")
    else
      data_rows = alliance_details_table.search("tr")
    end
    
      data_rows.each_with_index do |alliance_member_detail, i|
        if(alliance_member_detail.search("td").length == 4)
          member_votes = alliance_member_detail.search("td")[2].text.match(/(\d+)/)[1].to_i
          if(member_votes > 0)
            res.push({ keyfy_str(alliance_member_detail.search("td")[1].text) => member_votes })
          end
        end
    end
    res
  end
  
  def extract_tecnical_data(results, table)
    if(table != nil)
      [ :total_voters, :voted, 
        :total_votes, :abstinent,
        :valid, :null,
        :total_acts, :acts].each_with_index do |key, index|
        results[key] = table[index].css("td")[1].text.strip.to_i
      end
    end
  end
  
  def details_table_for_vote_type(vote_type, page)
    t = nil
    if([:asamblea_nominal, :asamblea_indigena].include?(vote_type))
      t = page.search("##{VOTE_TYPE_TO_ID[vote_type]}").search("table:nth-child(4) table:nth-child(2) table tr:nth-child(2n)")
    else
      t= page.search("##{VOTE_TYPE_TO_ID[vote_type]}").search("table:nth-child(3) table:nth-child(2) table tr:nth-child(2n)")
    end
    t
  end
  
  def admin_entities_from_navigation_panel(page)
    ents = []

    a_tags = page.search(".tabla_contenido")[1].css("a")
    
    if a_tags.length == 0
      a_tags = page.search(".tabla_contenido")[2].css("a")
    end
    
    a_tags.each do |a|
      ents.push({:name => keyfy_str(a.text), :breadcrumbs => @query_string.parse(a['href'])})
    end
    
    #{:name => 'amazonas', :breadcrumbs => {:state => "22"...}}
    #{:name => 'anzoategui', :breadcrumbs => {:state => "02"...}}
    #...
    ents
  end
end

@data = []

p = Parser.new(ARGV)
p.parse(@data)

