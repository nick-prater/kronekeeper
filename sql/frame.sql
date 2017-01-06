/*
This file is part of Kronekeeper, a web based application for 
recording and managing wiring frame records.

Copyright (C) 2016 NP Broadcast Limited

Kronekeeper is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as published
by the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

Kronekeeper is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with Kronekeeper.  If not, see <http://www.gnu.org/licenses/>.
*/



/* Initialises a regular, rectangular frame to specified dimensions,
 * creating the frame record and inserting the required number of
 * empty block positions.
 * 
 * Block designations are created, by default running
 * left-to-right and bottom-to-top. The ordering of these designations
 * can be reversed by setting the p_reverse_vertical_designations and
 * p_reverse_block_designations parameters to TRUE.
 * 
 * Returns the id of the newly created frame.
 */
CREATE OR REPLACE FUNCTION create_regular_frame(
	p_account_id INTEGER,
	p_name TEXT,
	p_vertical_count INTEGER,
	p_row_count INTEGER,
	p_reverse_vertical_designations BOOLEAN,
	p_reverse_row_designations BOOLEAN,
	p_is_template BOOLEAN
)
RETURNS INTEGER AS $$
DECLARE frame_id INTEGER;
DECLARE vertical_id INTEGER;
DECLARE vertical_designation TEXT;
DECLARE block_designation TEXT;
DECLARE maximum_size INTEGER := 500;
DECLARE designation_position INTEGER;
BEGIN
	
	/* Validation */
	CASE
		WHEN p_vertical_count IS NULL THEN
			RAISE EXCEPTION 'number of verticals cannot be NULL';
		WHEN p_vertical_count < 1 THEN
			RAISE EXCEPTION 'number of verticals cannot be less than 1';
		WHEN p_vertical_count > maximum_size THEN
			RAISE EXCEPTION 'number of verticals cannot be more than %', maximum_size;

		WHEN p_row_count IS NULL THEN
			RAISE EXCEPTION 'number of blocks in a vertical cannot be NULL';
		WHEN p_row_count < 1 THEN
			RAISE EXCEPTION 'number of blocks in a vertical cannot be less than 1';
		WHEN p_row_count > maximum_size THEN
			RAISE EXCEPTION 'number of blocks in a vertical cannot be more than %', maximum_size;

		ELSE -- validation OK
	END CASE;
		
	/* Create the frame */
	INSERT INTO frame(account_id, name, is_template)
	VALUES(p_account_id, p_name, p_is_template)
	RETURNING id INTO frame_id;

	RAISE DEBUG 'Inserted new frame with id:%', frame_id;

	/* Initialise the columns with empty blocks */
	FOR vertical_position IN 1..p_vertical_count LOOP

		/* Reversing vertical designations? */
		IF p_reverse_vertical_designations THEN
			designation_position := invert_position_index(vertical_position, p_vertical_count);
		ELSE
			designation_position := vertical_position;
		END IF;

		INSERT INTO vertical(frame_id, position, designation)
		VALUES(
			frame_id,
			vertical_position,
			regular_vertical_designation_from_position(designation_position)
		)
		RETURNING id, designation INTO vertical_id, vertical_designation;
		RAISE DEBUG 'Inserted vertical with designation %', vertical_designation;

		FOR block_position IN 1..p_row_count LOOP

			/* Reversing row designations? */
			IF p_reverse_row_designations THEN
				designation_position := invert_position_index(block_position, p_row_count);
			ELSE
				designation_position := block_position;
			END IF;

			INSERT INTO block(vertical_id, position, designation)
			VALUES(
				vertical_id,
				block_position,
				regular_block_designation_from_position(designation_position, p_row_count)
			)
			RETURNING designation INTO block_designation;
			RAISE NOTICE 'Inserted empty block with designation %', CONCAT(vertical_designation, block_designation);
		END LOOP;
	END LOOP;

	RETURN frame_id;
END
$$ LANGUAGE plpgsql;



/* For the given frame_id, reverse the order of the existing
 * vertical designations.
 * 
 * This depends on vertical.position values starting at
 * 1 and being contiguous. Should perhaps enforce that
 * as a data constraint...
 */
CREATE OR REPLACE FUNCTION reverse_vertical_designations(
	p_frame_id INTEGER
)
RETURNS BOOLEAN AS $$
DECLARE vertical_count INTEGER;
BEGIN

	/* Create a reference copy of the current designations */
	CREATE TEMPORARY TABLE temp_designation (
		position INTEGER PRIMARY KEY,
		designation TEXT
	)
	ON COMMIT DROP;
		    
	INSERT INTO temp_designation (position,	designation)
	SELECT position, designation
	FROM vertical
	WHERE frame_id = p_frame_id;

	/* How many verticals in total? */
	GET DIAGNOSTICS vertical_count = ROW_COUNT;

	/* Suspend unique constraint on designation during update */
	SET CONSTRAINTS vertical_unique_frame_designation DEFERRED;

	/* Then rename with the reversed designation sequence */
	UPDATE vertical
	SET designation = (
		SELECT designation
		FROM temp_designation AS t
		WHERE t.position = invert_position_index(
			vertical.position,
			vertical_count
		)
	)
	WHERE vertical.frame_id = p_frame_id;

	/* Restore unique constraint */
	SET CONSTRAINTS vertical_unique_frame_designation IMMEDIATE;

	RETURN FOUND;

END
$$ LANGUAGE plpgsql;



/* For the given frame_id, reverse the order of the existing
 * block designations.
 * 
 * This depends on vertical.position values starting at
 * 1 and being contiguous. Should perhaps enforce that
 * as a data constraint... Also, we cannot sensibly perform
 * this operation if there are differences in the number
 * of blocks present in each vertical, as it's unclear
 * where the missing blocks should be positioned or how
 * they should be labelled.
 */
CREATE OR REPLACE FUNCTION reverse_block_designations(
	p_frame_id INTEGER
)
RETURNS BOOLEAN AS $$
DECLARE min_block_count INTEGER;
DECLARE max_block_count INTEGER;
BEGIN

	/* How many blocks does each vertical have? */
	SELECT MAX(block_count), MIN(block_count)
	INTO max_block_count, min_block_count FROM (
		SELECT COUNT(*) AS block_count
		FROM block
		JOIN vertical ON (vertical.id = block.vertical_id)
		WHERE vertical.frame_id = p_frame_id
		GROUP BY vertical.id
	) AS t;

	/* Do all verticals have the same number of blocks?
	 * If not, we cannot automatically reverse/mirror the designations.
	 */
	IF max_block_count != min_block_count THEN
		RAISE EXCEPTION 'Cannot automatically reverse designations when number of blocks in each vertical differ';
	END IF;

	/* Create a reference copy of the current designations */
	CREATE TEMPORARY TABLE temp_designation (
		position INTEGER,
		vertical_id INTEGER,
		designation TEXT
	)
	ON COMMIT DROP;
		    
	INSERT INTO temp_designation (position,	vertical_id, designation)
	SELECT block.position, block.vertical_id, block.designation
	FROM block
	JOIN vertical ON (vertical.id = block.vertical_id)
	WHERE vertical.frame_id = p_frame_id;

	/* Suspend unique constraint on designation during update */
	SET CONSTRAINTS block_unique_vertical_designation DEFERRED;

	/* Then rename with the reversed designation sequence */
	UPDATE block
	SET designation = (
		SELECT designation
		FROM temp_designation AS t
		WHERE t.vertical_id = block.vertical_id
		AND t.position = invert_position_index(
			block.position,
			max_block_count
		)
	)
	FROM vertical
	WHERE vertical.id = block.vertical_id
	AND vertical.frame_id = p_frame_id;

	/* Restore unique constraint */
	SET CONSTRAINTS block_unique_vertical_designation IMMEDIATE;

	RETURN FOUND;

END
$$ LANGUAGE plpgsql;


CREATE OR REPLACE VIEW frame_info AS
SELECT
        frame.id,
	frame.account_id,
        frame.name,
        frame.is_deleted,
	frame.is_template,
        COALESCE(MAX(vertical.position), 0) AS vertical_count,
        COALESCE(MAX(block.position), 0) AS block_count
FROM frame
LEFT JOIN vertical ON (vertical.frame_id = frame.id)
LEFT JOIN block ON (block.vertical_id = vertical.id)
GROUP BY frame.id;


