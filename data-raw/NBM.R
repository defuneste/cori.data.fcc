## code to prepare `NBM` dataset goes here

library(cori.data.fcc)

dir <- "data_swamp/nbm/"

release <- get_nbm_release()

nbm_data <- get_nbm_available()

system(sprintf("mkdir -p %s", dir))

# this is a big loop
for (i in release$filing_subtype){
  dl_nbm(
    path_to_dl = "data_swamp/nbm",
    release_date = i,
    data_type = "Fixed Broadband",
    data_category = "Nationwide")
}

num_files <- nbm_data |>
  dplyr::filter(data_type == "Fixed Broadband" &
                  data_category == "Nationwide") |>
  nrow()
# echking if we have all the files
files_dl <- length(list.files(dir, pattern = "*.zip"))

stopifnot("we are missing some files" = identical(num_files, files_dl))

system(sprintf("mkdir -p %sraw", dir))

system(sprintf("unzip %s\\*.zip -d %sraw", dir, dir))

system(sprintf("du -sh %sraw", dir))
# 290G    data_swamp/nbm/raw

## files name follow some nice pattern but J23 or D22 are hard to convert in sql to a Date
# better do that in R

raw_csv <- list.files(dir, pattern = "*.csv", recursive = TRUE)
raw_csv <- paste0(dir, raw_csv)

better_fcc_name <- function(file_name) {

  convert_date <- function(string) {
    m <- substring(string, 1, 1)
    y <- substring(string, 2, 3)
    if (m == "D") month <- "December" else month <- "June"
    year <- paste0("20", y)
    paste0(month, year)
  }

  dir_name <- dirname(file_name)
  bad_file_name <- basename(file_name)
  split_bad_file_name <- unlist(strsplit(bad_file_name, split = "_"))
  split_bad_file_name[6] <- convert_date(split_bad_file_name[6])
  good_file_name <- paste(split_bad_file_name, collapse = "_")
  good_file_path <- paste(dir_name, good_file_name, sep = "/")
  return(good_file_path)
}

better_name <- vapply(raw_csv, better_fcc_name, FUN.VALUE = character(1))

file.rename(raw_csv, better_name)

library(duckdb)

con <- DBI::dbConnect(duckdb::duckdb(),  tempfile())

## I went overkill with that one, it is probably not needed
DBI::dbExecute(con, "PRAGMA max_temp_directory_size='10GiB'")

copy_stat <- "
COPY
    (SELECT 
      frn, 
      provider_id, 
      brand_name,
      location_id,
      technology,
      max_advertised_download_speed,
      max_advertised_upload_speed,
      low_latency,
      business_residential_code,
      state_usps,
      block_geoid as geoid_bl, 
      substring(block_geoid, 1, 5) as geoid_co,
      strptime(split_part(split_part(filename, '_', 8), '.', 1), '%d%b%Y')::DATE
       as file_time_stamp,
      strptime(split_part(filename, '_', 7), '%B%Y')::DATE as release 
    FROM 
    read_csv(
             'data_swamp/nbm/raw/*.csv',
              types = { 
                        'frn'        : 'VARCHAR(10)',
                        'provider_id': 'TEXT',
                        'brand_name' : 'TEXT',
                        'location_id': 'TEXT', 
                        'technology' : 'VARCHAR(2)', 
                        'max_advertised_download_speed' : INTEGER,
                        'max_advertised_upload_speed' : INTEGER,
                        'low_latency' : 'BOOLEAN',
                        'business_residential_code': 'VARCHAR(1)',
                        'state_usps' : 'VARCHAR(2)',
                        'block_geoid': 'VARCHAR(15)'  
    },   
              ignore_errors = true,         
              delim=',', quote='\"',
              new_line='\\n', skip=0, 
              header=true, filename=true))
    TO 'nbm_raw' (FORMAT 'parquet', PARTITION_BY(release, state_usps, technology)
    );"

DBI::dbExecute(con, copy_stat)

DBI::dbDisconnect(con)

system("aws s3 sync nbm_raw s3://cori.data.fcc/nbm_raw")

## update January 2025, adding June2024
# assuming list of csv in data_swamp

library(duckdb)

con <- DBI::dbConnect(duckdb::duckdb(),  tempfile())

# I needed to run because FCC naming J24 can be june, january ... 
dir <- "data_swamp/10dec2024/"

raw_csv <- list.files(dir, pattern = "*.csv", recursive = TRUE)
raw_csv <- paste0(dir, raw_csv)

# better names is defined above
better_name <- vapply(raw_csv, better_fcc_name, FUN.VALUE = character(1))

file.rename(raw_csv, better_name)


## I went overkill with that one, it is probably not needed
DBI::dbExecute(con, "PRAGMA max_temp_directory_size='10GiB'")

copy_stat <- "
COPY
    (SELECT 
      frn, 
      provider_id, 
      brand_name,
      location_id,
      technology,
      max_advertised_download_speed,
      max_advertised_upload_speed,
      low_latency,
      business_residential_code,
      state_usps,
      block_geoid as geoid_bl, 
      substring(block_geoid, 1, 5) as geoid_co,
      strptime(split_part(split_part(filename, '_', 8), '.', 1), '%d%b%Y')::DATE
       as file_time_stamp,
      strptime(split_part(filename, '_', 7), '%B%Y')::DATE as release 
    FROM 
    read_csv(
             'data_swamp/10dec2024/*.csv',
              types = { 
                        'frn'        : 'VARCHAR(10)',
                        'provider_id': 'TEXT',
                        'brand_name' : 'TEXT',
                        'location_id': 'TEXT', 
                        'technology' : 'VARCHAR(2)', 
                        'max_advertised_download_speed' : INTEGER,
                        'max_advertised_upload_speed' : INTEGER,
                        'low_latency' : 'BOOLEAN',
                        'business_residential_code': 'VARCHAR(1)',
                        'state_usps' : 'VARCHAR(2)',
                        'block_geoid': 'VARCHAR(15)'  
    },   
              ignore_errors = true,         
              delim=',', quote='\"',
              new_line='\\n', skip=0, 
              header=true, filename=true))
    TO 'nbm_raw' (FORMAT 'parquet', PARTITION_BY(release, state_usps, technology)
    );"

DBI::dbExecute(con, copy_stat)

DBI::dbDisconnect(con)

system("aws s3 sync nbm_raw/release=2024-06-01 s3://cori.data.fcc/nbm_raw/release=2024-06-01")
