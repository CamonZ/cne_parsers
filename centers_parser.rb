#!/usr/bin/env ruby -wKU

require 'csv'
require 'iconv'
require 'active_support/inflector'
require 'json'

COLUMN_NAMES = {
  "state_code" => 0,
  "state_name" => 1,
  "municipality_code" => 2,
  "municipality_name" => 3,
  "parish_code" => 4,
  "parish_name" => 5,
  "center_code" => 6,
  "center_name" => 7,
  "center_address" => 8,
  "tables_number" => 9,
  "automatized_tables_number" => 10,
  "venezuelans_number" => 11,
  "foreigners_number" => 12,
  "voters_number" => 13,
  "automatic_transmission_enabled" => 14
}

NEXT_DEPTH = {
  "state" => "municipality",
  "municipality" => "parish",
  "parish" => "center"
}

def states_hash(f)
  { "cne_code" => f[COLUMN_NAMES["state_code"]], "cne_name" => f[COLUMN_NAMES["state_name"]] }
end

def municipalities_hash(f)
  { "cne_code" => f[COLUMN_NAMES["municipality_code"]], "cne_name" => f[COLUMN_NAMES["municipality_name"]] }
end

def parishes_hash(f)
  { "cne_code" => f[COLUMN_NAMES["parish_code"]], "cne_name" => f[COLUMN_NAMES["parish_name"]] }
end

def centers_hash(f)
  res = {
    "cne_code" => f[COLUMN_NAMES["center_code"]],
    "cne_name" => f[COLUMN_NAMES["center_name"]],
    "address" => f[COLUMN_NAMES["center_address"]],
    "tables_number" => f[COLUMN_NAMES["tables_number"]],
    "automatized_tables_number" => f[COLUMN_NAMES["automatized_tables_number"]],
    "venezuelans_number" => f[COLUMN_NAMES["venezuelans_number"]],
    "foreigners_number" => f[COLUMN_NAMES["foreigners_number"]],
    "voters" => f[COLUMN_NAMES["voters_number"]]
  }
  
  if f.length == 15
    res["automatic_transmission_enabled"] = f[COLUMN_NAMES["automatic_transmission_enabled"]] 
  end
  
  res
end

def hash_for(entity, f)
  self.send("#{entity.pluralize}_hash".to_sym, f)
end

def parse(hash, entity, f)
  if(!hash.has_key?(f[COLUMN_NAMES["#{entity}_code"]]))
    hash[f[COLUMN_NAMES["#{entity}_code"]]] = hash_for(entity, f)
  end
  
  if(entity == "center")
    return hash
  else
    
    next_depth = NEXT_DEPTH[entity]
    
    if(!hash[f[COLUMN_NAMES["#{entity}_code"]]].has_key?(next_depth.pluralize))
      hash[f[COLUMN_NAMES["#{entity}_code"]]][next_depth.pluralize] = {}
    end
    
    parse(hash[f[COLUMN_NAMES["#{entity}_code"]]][next_depth.pluralize], next_depth, f)
    
  end
end

@results = {}

csv_file = File.open("TABLA CENTRO Eleccion_Presidencial_07102012.csv")
ic = Iconv.new('UTF-8//IGNORE', 'UTF-8')

lines = csv_file.readlines
lines.shift #discard first line

lines.each_with_index do |l, index|
  valid_string = ic.iconv(l + ' ')[0..-2]
  
  if(valid_string[-3] == ";")
    valid_string.slice!(-3, 1)
  end
  
  fields = valid_string.parse_csv(:col_sep => ";").map{|k| k.downcase }
  parse(@results, "state", fields)
end

output = File.new("centros_2.json", "w")
output << @results.to_json
output.close