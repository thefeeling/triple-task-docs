create schema triple collate utf8mb4_unicode_ci;

create table triple.attachments
(
  id         binary(16) not null comment 'PK' primary key,
  url        text       not null comment 'ACCESS_URL',
  created_at datetime   not null,
  updated_at datetime   not null
) ENGINE = InnoDB
  comment '첨부파일';

create table triple.places
(
  id         binary(16)   not null comment 'PK' primary key,
  lat        float        not null comment '위도',
  lng        float        not null comment '경도',
  title      varchar(255) not null comment '장소명',
  created_at datetime     not null,
  updated_at datetime     not null
) ENGINE = InnoDB
  comment '장소';


create table triple.point_policies
(
  id         bigint auto_increment primary key,
  type       varchar(10) not null comment '정책 타입(REVIEW, EVENT 등)',
  title      varchar(50) not null comment '정책명',
  amount     int         not null comment '지급금액',
  expire_day int         not null comment '만료일자',
  use_yn     bit         not null comment '사용유무',
  start_date datetime    not null comment '시작일자',
  end_date   datetime    not null comment '종료일자',
  created_at datetime    not null,
  updated_at datetime    not null
) ENGINE = InnoDB
  comment '포인트_정책';

create table triple.users
(
  id         binary(16)   not null comment 'PK' primary key,
  email      varchar(100) not null comment '이메일',
  name       varchar(50)  not null comment '이름',
  password   text         not null comment '패스워드',
  created_at datetime     not null,
  updated_at datetime     not null
) ENGINE = InnoDB
  comment '유저';


create table triple.points
(
  id              bigint auto_increment comment 'PK' primary key,
  original_id     bigint      not null comment '포인트_원본ID: 사용/차감/만료 시 원본유지, 적립의 경우도 ID값과 동일하게 유지',
  status          varchar(10) not null comment 'SAVE(적립), DELETE(차감), USE(사용), EXPIRE(만료)',
  amount          int         not null comment '포인트',
  user_id         binary(16)  not null comment 'FK: 유저ID',
  point_policy_id bigint      not null comment 'FK: 포인트_정책_ID',
  expired_at      date        not null comment '만료일자:YYYY-MM-DD',
  created_at      datetime    not null,
  updated_at      datetime    not null,
  constraint FK_POINT_POINT_POLICY_ID
    foreign key (point_policy_id) references triple.point_policies (id),
  constraint FK_POINT_USER_ID
    foreign key (user_id) references triple.users (id)
) ENGINE = InnoDB
  comment '포인트';

create table triple.reviews
(
  id              binary(16) not null comment 'PK' primary key,
  place_id        binary(16) not null comment 'FK: 장소ID',
  user_id         binary(16) not null comment 'FK: 유저ID',
  content         text       not null comment '리뷰_텍스트',
  attached_photos text       not null comment '첨부이미지: Comma-Base로 Attachment의 ID를 저장',
  created_at      datetime   not null,
  updated_at      datetime   not null,
  deleted_at      datetime   null comment '삭제일자: SoftDelete를 위하여 사용',
  constraint UNIQUE_REVIEW
    unique (place_id, user_id),
  constraint FK_REVIEW_PLACE_ID
    foreign key (place_id) references triple.places (id),
  constraint FK_REVIEW_USER_ID
    foreign key (user_id) references triple.users (id)
) ENGINE = InnoDB
  comment '리뷰';


create table triple.review_points
(
  id         bigint auto_increment comment 'PK' primary key,
  review_id  binary(16) not null comment 'FK: 리뷰ID',
  user_id    binary(16) not null comment 'FK: 유저ID',
  content    text       not null comment '보관이력: JSON Array String',
  created_at datetime   not null,
  constraint FK_REVIEW_POINT_REVIEW_ID
    foreign key (review_id) references triple.reviews (id),
  constraint FK_REVIEW_POINT_USER_ID
    foreign key (user_id) references triple.users (id)
) ENGINE = InnoDB
  comment '리뷰_포인트_히스토리';
