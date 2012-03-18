module NurseBulkUploader
  
  attr_reader :parsing_errors
  
  PossibleColumns = [:name, :num_weeks_off, :years_worked]
  RequiredColumns = [:name, :num_weeks_off]

  def replace_from_spreadsheet(file_path, unit, shift)
    uploader = Uploader.new(unit, shift)
    uploader.replace_from_spreadsheet(file_path)
    @parsing_errors = uploader.parsing_errors
  end
  
  class Uploader
    
    attr_accessor :unit, :shift, :parsing_errors, :sheet, :cols
    
    def initialize(unit, shift)
      self.unit = unit
      self.shift = shift
      self.initialize_error_messages
    end
    
    def replace_from_spreadsheet(file_path)
      return if !load_from_file(file_path)
      return if !set_column_positions
      destroy_original_nurses
      create_nurses
    end
    
    def load_from_file(file_path)
      case File.extname(file_path)
      when '.xls' then type = Excel
      when '.xlsx' then type = Excelx
      end
      if type
        @sheet = type.new(file_path)
        true # indicator if method call was success
      else
        error_invalid_type
        false
      end
    end
    
    def set_column_positions
      self.initialize_columns
      start_col = sheet.first_column
      end_col = sheet.last_column
      
      if start_col and end_col      
        start_col.upto (end_col) do |col|
          associate_column(sheet.first_row, col)
          break if all_cols_associated # avoid going through extra columns
        end
      end
      
      if !necessary_cols_associated
        error_missing_headers
        false
      else
        true
      end
    end
    
    def destroy_original_nurses     
      self.parsing_errors[:database_changed] = true
      @unit.nurses.where(:shift => self.shift).destroy_all
    end
    
    def create_nurses
      start_row = sheet.first_row + 1 # skip header row
      seniority_counter = 1
      start_row.upto(sheet.last_row) do |row|
        create_nurse(row, seniority_counter)
        seniority_counter += 1
      end
    end
    
    def create_nurse(row, count)
      years_worked = (cols[:years_worked])? sheet.cell(row, cols[:years_worked]) : nil
      nurse = Nurse.new(:seniority => count,
                        :unit => self.unit,
                        :shift => self.shift,
                        :name => sheet.cell(row, cols[:name]),
                        :num_weeks_off => sheet.cell(row, cols[:num_weeks_off]),
                        :years_worked => years_worked)
      nurse.save
      set_creation_errors(row, nurse.errors)
    end
    
    def set_creation_errors(row, errors)
      nurse_errors = errors.full_messages.map {|message| "Nurse in row #{row}: " + message}
      self.parsing_errors[:messages] = (self.parsing_errors[:messages] << nurse_errors).flatten
    end
    
    def associate_column(row, col)
      cell = @sheet.cell(row, col)
      cell = cell.downcase if cell
      
      cols[:name] = col if match_name cell
      cols[:num_weeks_off] = col if match_num_weeks_off cell
      cols[:years_worked] = col if match_years_worked cell
    end
    
    def match_name(cell)
      cell =~ /^(?:code)?name$/
    end
    
    def match_num_weeks_off(cell)
      cell =~ /^num(?:ber)? (?:of )?weeks off$/
    end
    
    def match_years_worked(cell)
      cell =~ /^years(?: worked)?$/
    end
    
    def necessary_cols_associated
      check_hash_assoc RequiredColumns
    end
    
    def all_cols_associated
      check_hash_assoc PossibleColumns
    end
    
    def check_hash_assoc(params_to_check)
      params_to_check.each do |term|
        return false if !self.cols[term]
      end
      return true
    end
    
    def initialize_error_messages
      self.parsing_errors = {}
      self.parsing_errors[:database_changed] = false
      self.parsing_errors[:messages] = []
    end
    
    def initialize_columns
      keys = [:name, :years_worked, :num_weeks_off]
      self.cols = Hash[*keys.zip([nil]*keys.size).flatten]
    end
    
    def error_invalid_type
      self.parsing_errors[:messages] << 'File to parse was not a valid xls or xlsx'
    end
    
    def error_missing_headers
      RequiredColumns.each do |term|
        self.parsing_errors[:messages] << missing_header_message(term) if !cols[term]
      end
    end
    
    def missing_header_message(sym)
      "Header row is missing the #{nice_col_name(sym)} column"
    end
    
    def nice_col_name(sym)
      sym.to_s.split('_').map{ |word| word.capitalize }.join(' ')
    end
    
  end
  
end
