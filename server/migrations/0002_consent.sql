-- Record of consent (GDPR Art. 7(1): the controller must be able to show
-- that the person agreed; Bahrain PDPL: processing based on consent).
-- Which version of the privacy notice and of the terms of use were accepted
-- (separately, in the app), and when (server time).
ALTER TABLE users ADD COLUMN privacy_version TEXT;
ALTER TABLE users ADD COLUMN terms_version TEXT;
ALTER TABLE users ADD COLUMN consent_at INTEGER;
