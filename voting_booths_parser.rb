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
  "table_number" => 9,
  "voters_number" => 10,
}

@results = {}

csv_file = File.open("TABLA MESA Eleccion_Presidencial_07102012.csv")
ic = Iconv.new('UTF-8//IGNORE', 'UTF-8')

lines = csv_file.readlines
lines.shift #discard first line
c = 0
lines.each_with_index do |l, index|
  valid_string = ic.iconv(l + ' ')[0..-2]
  
  if(valid_string[-3] == ";")
    valid_string.slice!(-3, 1)
  end
  
  fields = valid_string.parse_csv(:col_sep => ";").map{|k| k.downcase }

  if(!@results.has_key?(fields[COLUMN_NAMES["center_code"]]))
    @results[fields[COLUMN_NAMES["center_code"]]] = []
  end
  
  @results[fields[COLUMN_NAMES["center_code"]]].push({
    :booth_number => fields[COLUMN_NAMES["table_number"]], 
    :voters => fields[COLUMN_NAMES["voters_number"]]
  })
  
  c+=1
end
puts "#{c} lineas procesadas"
output = File.new("voting_booths_by_center.json", "w")
output << @results.to_json
output.close