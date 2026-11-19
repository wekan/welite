-- Expand the demo once. Existing sample rows can have been edited by the user.
CREATE TABLE IF NOT EXISTS _wl_example_batches (name TEXT PRIMARY KEY);
CREATE TEMP TABLE example_expansion AS
SELECT id FROM boards WHERE id='example'
  AND NOT EXISTS (SELECT 1 FROM _wl_example_batches WHERE name='garden-work');
WITH lanes(id,title,color,position) AS (
 VALUES ('seedlings','Seedlings','#edf4c6',3), ('orchard','Orchard','#ffe0cc',4),
        ('supplies','Supplies','#f3dfef',5), ('events','Community events','#d7ecf0',6),
        ('harvest','Harvest','#ffecc7',7), ('winter','Winter preparation','#e5e1f5',8)
)
INSERT INTO swimlanes(id,boardId,title,color,sort,createdAt)
SELECT lanes.id, example_expansion.id,title,color,position,datetime('now')
FROM lanes CROSS JOIN example_expansion WHERE true ON CONFLICT(id) DO NOTHING;

WITH stages(number,title,color) AS (
 VALUES (1,'To do','#f8e3ae'), (2,'In progress','#cbe1ff'), (3,'Done','#c9e8cf'),
        (4,'Review','#f1dff2'), (5,'Waiting','#f9ddcd'), (6,'Ready','#d5eef2'),
        (7,'Scheduled','#e4d9f7'), (8,'Materials','#f7ebcd'), (9,'Follow-up','#e4eece'),
        (10,'Reference','#dedede')
)
INSERT INTO lists(id,boardId,swimlaneId,title,color,sort,createdAt)
SELECT lane.id || stage.number,lane.boardId,lane.id,stage.title,stage.color,stage.number,datetime('now')
FROM swimlanes lane JOIN example_expansion b ON b.id=lane.boardId CROSS JOIN stages stage
WHERE lane.id IN ('planning','garden','seedlings','orchard','supplies','events','harvest','winter')
ON CONFLICT(id) DO NOTHING;

WITH work(slot,verb,color,userId) AS (
 VALUES (1,'Prepare','#fff2c2','examplealex'),
        (2,'Check','#ddeaff','examplesam'),
        (3,'Document','#d8f1db','examplelee')
), tasks AS (
 SELECT l.id AS listId,l.boardId,s.id AS laneId,s.title AS laneTitle,l.title AS listTitle,
        work.*,row_number() OVER (ORDER BY s.sort,l.sort,work.slot,l.id) AS n
 FROM lists l JOIN swimlanes s ON s.id=l.swimlaneId AND s.boardId=l.boardId
 JOIN example_expansion b ON b.id=l.boardId CROSS JOIN work
 JOIN users u ON u.id=work.userId
 WHERE s.id IN ('planning','garden','seedlings','orchard','supplies','events','harvest','winter')
   AND l.sort BETWEEN 1 AND 10 AND l.id=s.id||CAST(l.sort AS INTEGER)
)
INSERT INTO cards(id,boardId,listId,swimlaneId,title,description,color,userId,sort,cardNumber,dueAt,dateLastActivity,createdAt,modifiedAt)
SELECT 'examplework-'||listId||'-'||slot,boardId,listId,laneId,
 verb||' '||lower(laneTitle)||' work',listTitle||': record progress and the next step.',
 color,userId,100+slot,1000+n,
 CASE WHEN slot=1 THEN strftime('%Y-%m-%dT12:00:00.000Z','now','start of month','+'||(n%28)||' days') END,
 datetime('now'),datetime('now'),datetime('now') FROM tasks WHERE true ON CONFLICT(id) DO NOTHING;

INSERT INTO _wl_example_batches(name) SELECT 'garden-work' FROM example_expansion;
DROP TABLE example_expansion;
