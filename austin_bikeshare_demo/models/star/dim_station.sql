SELECT DISTINCT
    station_id,
    name,
    status,
    location,
    address,
    alternate_name,
    city_asset_number,
    property_type,
    number_of_docks,
    power_type,
    footprint_length,
    footprint_width,
    notes,
    council_district,
    image,
    modified_date
FROM {{ source('austin_bikeshare', 'bikeshare_stations') }}