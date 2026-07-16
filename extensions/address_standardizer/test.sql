-- address_standardizer (parse/normalize postal addresses) tests.
CREATE EXTENSION IF NOT EXISTS address_standardizer;
CREATE EXTENSION IF NOT EXISTS address_standardizer_data_us;

SELECT CASE WHEN (SELECT count(*) FROM pg_extension WHERE extname='address_standardizer')=1
    THEN 'PASS address_standardizer: extension loads' ELSE 'FAIL address_standardizer: extension loads' END;

-- parse a US street address into its components
SELECT CASE WHEN (standardize_address('us_lex','us_gaz','us_rules','123 Main St, Springfield')).house_num = '123'
    THEN 'PASS address_standardizer: extracts house number'
    ELSE 'FAIL address_standardizer: extracts house number' END;
