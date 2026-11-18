-- Applied only to a new database by the build menu.
INSERT INTO users(id, username, isAdmin, createdAt, modifiedAt, services_json)
SELECT id, username, isAdmin, datetime('now'), datetime('now'), example_credentials.services
FROM (
  SELECT 'examplealex' AS id, 'alex' AS username, 1 AS isAdmin
  UNION ALL SELECT 'examplesam', 'sam', 0
  UNION ALL SELECT 'examplelee', 'lee', 0
), example_credentials;

INSERT INTO boards(id,title,slug,description,color,createdAt)
VALUES('example','Community garden','community-garden','Plan, plant, and share the harvest.','#cce5d5',datetime('now'));
INSERT INTO board_members(boardId,userId,isAdmin)
SELECT 'example', id, isAdmin FROM users;

INSERT INTO swimlanes(id,boardId,title,color,sort,createdAt) VALUES
 ('planning','example','Planning','#dceaf7',1,datetime('now')),
 ('garden','example','In the garden','#e2efcf',2,datetime('now'));
INSERT INTO lists(id,boardId,swimlaneId,title,color,sort,createdAt)
SELECT lane.id || stage.number, 'example', lane.id, stage.title, stage.color, stage.number, datetime('now')
FROM swimlanes AS lane CROSS JOIN (
  SELECT 1 AS number, 'To do' AS title, '#f8e3ae' AS color
  UNION ALL SELECT 2, 'In progress', '#cbe1ff'
  UNION ALL SELECT 3, 'Done', '#c9e8cf'
) AS stage;

WITH sample(number,lane,stage,title,description,color,author,due_day) AS (
 VALUES
  (1,'planning',1,'Order seeds','Compare varieties and confirm quantities.','#fff2c2','examplealex',3),
  (2,'planning',1,'Invite volunteers','Share the signup sheet with neighbours.','#ffe0db','examplesam',5),
  (3,'planning',2,'Draw the plot map','Mark beds and accessible paths.','#ddeaff','examplelee',8),
  (4,'planning',3,'Book the kickoff','Confirm the community room.','#d8f1db','examplealex',NULL),
  (5,'garden',1,'Plant the herb bed','Label parsley, thyme, and mint.','#fff2c2','examplesam',12),
  (6,'garden',2,'Prepare the raised beds','Add compost before planting.','#e8dfff','examplelee',15),
  (7,'garden',2,'Check irrigation','Test the hose and note any leaks.','#ddeaff','examplesam',17),
  (8,'garden',3,'Build the tool rack','Leave room for shared hand tools.','#d8f1db','examplealex',NULL)
)
INSERT INTO cards(id,boardId,listId,swimlaneId,title,description,color,userId,sort,cardNumber,dueAt,dateLastActivity,createdAt,modifiedAt)
SELECT 'examplecard'||number,'example',lane||stage,lane,title,description,color,author,number,number,
 CASE WHEN due_day IS NOT NULL THEN strftime('%Y-%m-%dT12:00:00.000Z','now','start of month','+'||(due_day-1)||' days') END,
 datetime('now'),datetime('now'),datetime('now') FROM sample;

INSERT INTO board_labels(boardId,id,name,color) VALUES
 ('example','garden','Outdoor','#76bd89'),('example','team','Team','#7eb6e8');
INSERT INTO card_labels(cardId,labelId) VALUES
 ('examplecard2','team'),('examplecard5','garden'),('examplecard6','garden');
INSERT INTO card_assignees(cardId,userId)
SELECT id,userId FROM cards;
