-- =====================================================================
--  Spelling Bee - Esquema PostgreSQL
--  Basado en el SRS (rev. 1.0) y en el diagrama ER acordado.
--  Probado en PostgreSQL 16 (usa columnas IDENTITY, requiere 10+).
--
--  Convenciones:
--    * Todas las columnas son NOT NULL, salvo las que el SRS deja
--      opcionales o "libres" (se indican con el comentario  -- NULL).
--    * Estados en minusculas y sin acentos.
--    * Las reglas que cruzan tablas (misma pertenencia al concurso,
--      limites, etc.) se validan con triggers al final del script.
-- =====================================================================

-- Para volver a crear todo desde cero (BORRA TODOS LOS DATOS):
-- DROP TABLE IF EXISTS participacion_ronda, carta_podio, calificacion, turno,
--     palabra, juez, participante, ronda, concurso, administrador CASCADE;

BEGIN;

-- ---------------------------------------------------------------------
-- ADMINISTRADOR  (RF-17: entra con usuario y contrasena)
-- ---------------------------------------------------------------------
CREATE TABLE administrador (
    id_administrador  INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    usuario           VARCHAR(50)  NOT NULL,
    contrasena_hash   TEXT         NOT NULL,   -- nunca texto plano (3.5.2)
    CONSTRAINT uq_administrador_usuario UNIQUE (usuario),
    CONSTRAINT ck_administrador_usuario CHECK (btrim(usuario) <> ''),
    CONSTRAINT ck_administrador_hash    CHECK (btrim(contrasena_hash) <> '')
);

-- ---------------------------------------------------------------------
-- CONCURSO  (RF-03, R-01, R-03)
-- ---------------------------------------------------------------------
CREATE TABLE concurso (
    id_concurso           INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre                VARCHAR(100) NOT NULL,
    fecha                 DATE         NOT NULL,
    hora                  TIME,                          -- NULL: la hora es opcional
    limite_participantes  INTEGER,                       -- NULL: sin limite ("libre")
    numero_jueces         SMALLINT,                      -- NULL: sin numero fijado (tope R-01: 5)
    estado                VARCHAR(10)  NOT NULL DEFAULT 'proximo',
    CONSTRAINT ck_concurso_nombre  CHECK (btrim(nombre) <> ''),
    CONSTRAINT ck_concurso_limite  CHECK (limite_participantes IS NULL OR limite_participantes > 0),
    CONSTRAINT ck_concurso_jueces  CHECK (numero_jueces IS NULL OR numero_jueces BETWEEN 1 AND 5),
    CONSTRAINT ck_concurso_estado  CHECK (estado IN ('proximo', 'en_curso', 'finalizado'))
);

-- ---------------------------------------------------------------------
-- PARTICIPANTE  (RF-01)
-- ---------------------------------------------------------------------
CREATE TABLE participante (
    id_participante  INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_concurso      INTEGER      NOT NULL REFERENCES concurso (id_concurso)
                                  ON UPDATE CASCADE ON DELETE RESTRICT,
    apellido         VARCHAR(100) NOT NULL,
    nombre           VARCHAR(100) NOT NULL,
    escuela          VARCHAR(100) NOT NULL,
    estado           VARCHAR(10)  NOT NULL DEFAULT 'activo',
    CONSTRAINT ck_participante_apellido CHECK (btrim(apellido) <> ''),
    CONSTRAINT ck_participante_nombre   CHECK (btrim(nombre)   <> ''),
    CONSTRAINT ck_participante_escuela  CHECK (btrim(escuela)  <> ''),
    CONSTRAINT ck_participante_estado   CHECK (estado IN ('activo', 'eliminado'))
);
-- No registrar dos veces al mismo participante dentro del mismo evento
CREATE UNIQUE INDEX uq_participante_evento
    ON participante (id_concurso, lower(btrim(apellido)), lower(btrim(nombre)), lower(btrim(escuela)));

-- ---------------------------------------------------------------------
-- JUEZ  (RF-02, RF-17, 3.5.2)
-- El juez pertenece a un solo concurso; su codigo solo sirve en el.
-- ---------------------------------------------------------------------
CREATE TABLE juez (
    id_juez        INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_concurso    INTEGER      NOT NULL REFERENCES concurso (id_concurso)
                                ON UPDATE CASCADE ON DELETE RESTRICT,
    nombre         VARCHAR(100) NOT NULL,
    semblanza      TEXT,                                 -- NULL: es opcional (max. 120 palabras)
    codigo_acceso  VARCHAR(30)  NOT NULL,
    estado         VARCHAR(10)  NOT NULL DEFAULT 'activo',
    CONSTRAINT uq_juez_codigo      UNIQUE (codigo_acceso),
    CONSTRAINT ck_juez_nombre      CHECK (btrim(nombre) <> ''),
    CONSTRAINT ck_juez_codigo      CHECK (codigo_acceso ~ '^[A-Za-z0-9]{8,30}$'),
    CONSTRAINT ck_juez_semblanza   CHECK (semblanza IS NULL
                                          OR array_length(regexp_split_to_array(btrim(semblanza), '\s+'), 1) <= 120),
    CONSTRAINT ck_juez_estado      CHECK (estado IN ('activo', 'oculto', 'eliminado'))
);

-- ---------------------------------------------------------------------
-- PALABRA  (RF-04, R-04)
-- ---------------------------------------------------------------------
CREATE TABLE palabra (
    id_palabra   INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_concurso  INTEGER      NOT NULL REFERENCES concurso (id_concurso)
                              ON UPDATE CASCADE ON DELETE RESTRICT,
    texto        VARCHAR(100) NOT NULL,
    dificultad   VARCHAR(10)  NOT NULL,
    estado       VARCHAR(10)  NOT NULL DEFAULT 'disponible',
    CONSTRAINT ck_palabra_texto      CHECK (texto ~ '^[A-Za-z]+$'),      -- solo letras, sin espacios
    CONSTRAINT ck_palabra_dificultad CHECK (dificultad IN ('facil', 'intermedia', 'dificil')),
    CONSTRAINT ck_palabra_estado     CHECK (estado IN ('disponible', 'usada'))
);
-- No repetir palabras dentro del mismo nivel
CREATE UNIQUE INDEX uq_palabra_nivel ON palabra (id_concurso, dificultad, lower(texto));

-- ---------------------------------------------------------------------
-- RONDA  (R-03: 3 rondas por concurso; se crean solas con el concurso)
-- ---------------------------------------------------------------------
CREATE TABLE ronda (
    id_ronda              INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_concurso           INTEGER     NOT NULL REFERENCES concurso (id_concurso)
                                      ON UPDATE CASCADE ON DELETE RESTRICT,
    numero_ronda          SMALLINT    NOT NULL,
    estado                VARCHAR(10) NOT NULL DEFAULT 'pendiente',
    eliminados_mostrados  BOOLEAN     NOT NULL DEFAULT FALSE,
    CONSTRAINT uq_ronda_numero  UNIQUE (id_concurso, numero_ronda),
    CONSTRAINT ck_ronda_numero  CHECK (numero_ronda BETWEEN 1 AND 3),
    CONSTRAINT ck_ronda_estado  CHECK (estado IN ('pendiente', 'en_curso', 'cerrada'))
);

-- ---------------------------------------------------------------------
-- TURNO  (RF-05, RF-11, RF-12)
-- ---------------------------------------------------------------------
CREATE TABLE turno (
    id_turno            INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_ronda            INTEGER     NOT NULL REFERENCES ronda (id_ronda)
                                    ON UPDATE CASCADE ON DELETE RESTRICT,
    id_participante     INTEGER     NOT NULL REFERENCES participante (id_participante)
                                    ON UPDATE CASCADE ON DELETE RESTRICT,
    id_palabra          INTEGER     NOT NULL REFERENCES palabra (id_palabra)
                                    ON UPDATE CASCADE ON DELETE RESTRICT,
    numero_orden        INTEGER     NOT NULL,
    es_muerte_subita    BOOLEAN     NOT NULL DEFAULT FALSE,
    tiempo_limite       INTEGER,                         -- NULL: solo aplica en muerte subita (segundos)
    estado              VARCHAR(10) NOT NULL DEFAULT 'pendiente',
    puntaje_turno       INTEGER     NOT NULL DEFAULT 0,  -- lo mantiene un trigger (suma de calificaciones)
    puntaje_incompleto  BOOLEAN     NOT NULL DEFAULT FALSE,
    CONSTRAINT uq_turno_palabra  UNIQUE (id_palabra),                 -- una palabra usada no se reasigna
    CONSTRAINT uq_turno_orden    UNIQUE (id_ronda, numero_orden),
    CONSTRAINT ck_turno_orden    CHECK (numero_orden >= 1),
    CONSTRAINT ck_turno_estado   CHECK (estado IN ('pendiente', 'abierto', 'cerrado')),
    CONSTRAINT ck_turno_puntaje  CHECK (puntaje_turno >= 0),
    CONSTRAINT ck_turno_tiempo   CHECK (
        (es_muerte_subita     AND tiempo_limite IS NOT NULL AND tiempo_limite > 0)
     OR (NOT es_muerte_subita AND tiempo_limite IS NULL))
);
-- Un participante tiene un solo turno normal por ronda (los de muerte subita pueden ser varios)
CREATE UNIQUE INDEX uq_turno_normal_por_ronda
    ON turno (id_ronda, id_participante) WHERE NOT es_muerte_subita;

-- ---------------------------------------------------------------------
-- CALIFICACION  (RF-08, R-02)
-- ---------------------------------------------------------------------
CREATE TABLE calificacion (
    id_calificacion     INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_turno            INTEGER     NOT NULL REFERENCES turno (id_turno)
                                    ON UPDATE CASCADE ON DELETE RESTRICT,
    id_juez             INTEGER     NOT NULL REFERENCES juez (id_juez)
                                    ON UPDATE CASCADE ON DELETE RESTRICT,
    puntaje             SMALLINT    NOT NULL,
    fecha_calificacion  TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_calificacion_voto   UNIQUE (id_turno, id_juez),     -- un voto por juez y turno
    CONSTRAINT ck_calificacion_rango  CHECK (puntaje BETWEEN 0 AND 3)
);

-- ---------------------------------------------------------------------
-- PARTICIPACION_RONDA  (RF-10, RF-13, RF-14)
-- Una fila por participante al cerrar cada ronda.
-- ---------------------------------------------------------------------
CREATE TABLE participacion_ronda (
    id_participacion   INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_ronda           INTEGER     NOT NULL REFERENCES ronda (id_ronda)
                                   ON UPDATE CASCADE ON DELETE RESTRICT,
    id_participante    INTEGER     NOT NULL REFERENCES participante (id_participante)
                                   ON UPDATE CASCADE ON DELETE RESTRICT,
    puntaje_ronda      INTEGER     NOT NULL DEFAULT 0,
    puntaje_acumulado  INTEGER     NOT NULL DEFAULT 0,
    posicion           INTEGER     NOT NULL,
    estado             VARCHAR(10) NOT NULL DEFAULT 'continua',
    CONSTRAINT uq_participacion        UNIQUE (id_ronda, id_participante),
    CONSTRAINT ck_participacion_ronda  CHECK (puntaje_ronda >= 0),
    CONSTRAINT ck_participacion_acum   CHECK (puntaje_acumulado >= puntaje_ronda),
    CONSTRAINT ck_participacion_pos    CHECK (posicion >= 1),
    CONSTRAINT ck_participacion_estado CHECK (estado IN ('continua', 'eliminado'))
);

-- ---------------------------------------------------------------------
-- CARTA_PODIO  (RF-15, RF-16)
-- ---------------------------------------------------------------------
CREATE TABLE carta_podio (
    id_carta         INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_concurso      INTEGER  NOT NULL REFERENCES concurso (id_concurso)
                              ON UPDATE CASCADE ON DELETE RESTRICT,
    id_participante  INTEGER  NOT NULL REFERENCES participante (id_participante)
                              ON UPDATE CASCADE ON DELETE RESTRICT,
    lugar            SMALLINT NOT NULL,
    revelada         BOOLEAN  NOT NULL DEFAULT FALSE,
    CONSTRAINT uq_carta_lugar        UNIQUE (id_concurso, lugar),
    CONSTRAINT uq_carta_participante UNIQUE (id_participante),
    CONSTRAINT ck_carta_lugar        CHECK (lugar BETWEEN 1 AND 3)
);

-- Indices para las llaves foraneas que se consultan seguido
CREATE INDEX ix_participante_concurso ON participante (id_concurso);
CREATE INDEX ix_juez_concurso         ON juez (id_concurso);
CREATE INDEX ix_palabra_concurso      ON palabra (id_concurso, dificultad, estado);
CREATE INDEX ix_turno_participante    ON turno (id_participante);
CREATE INDEX ix_calificacion_juez     ON calificacion (id_juez);
CREATE INDEX ix_participacion_partic  ON participacion_ronda (id_participante);

-- =====================================================================
--  TRIGGERS: reglas que una restriccion CHECK/FK simple no puede cubrir
-- =====================================================================

-- ---- CONCURSO: fecha no pasada al crear; tras iniciar no cambian jueces ni limite por debajo de inscritos
CREATE FUNCTION fn_concurso_validar() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.fecha < CURRENT_DATE THEN
            RAISE EXCEPTION 'La fecha del concurso no puede estar en el pasado (%).', NEW.fecha;
        END IF;
    ELSE
        IF OLD.estado <> 'proximo'
           AND NEW.numero_jueces IS DISTINCT FROM OLD.numero_jueces THEN
            RAISE EXCEPTION 'Una vez iniciado, el concurso no puede cambiar su numero de jueces.';
        END IF;
        IF NEW.limite_participantes IS NOT NULL
           AND NEW.limite_participantes < (SELECT count(*) FROM participante WHERE id_concurso = NEW.id_concurso) THEN
            RAISE EXCEPTION 'El limite de participantes es menor a los ya inscritos.';
        END IF;
        IF NEW.numero_jueces IS NOT NULL
           AND NEW.numero_jueces < (SELECT count(*) FROM juez
                                    WHERE id_concurso = NEW.id_concurso AND estado = 'activo') THEN
            RAISE EXCEPTION 'El numero de jueces es menor a los jueces activos ya registrados.';
        END IF;
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_concurso_validar
    BEFORE INSERT OR UPDATE ON concurso
    FOR EACH ROW EXECUTE FUNCTION fn_concurso_validar();

-- ---- CONCURSO: al crearlo se generan sus 3 rondas (R-03)
CREATE FUNCTION fn_concurso_crear_rondas() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO ronda (id_concurso, numero_ronda)
    SELECT NEW.id_concurso, n FROM generate_series(1, 3) AS n;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_concurso_crear_rondas
    AFTER INSERT ON concurso
    FOR EACH ROW EXECUTE FUNCTION fn_concurso_crear_rondas();

-- ---- PARTICIPANTE: solo se registra con el concurso "proximo" y sin pasar el limite (RF-01)
CREATE FUNCTION fn_participante_validar() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_estado  VARCHAR(10);
    v_limite  INTEGER;
BEGIN
    SELECT estado, limite_participantes INTO v_estado, v_limite
      FROM concurso WHERE id_concurso = NEW.id_concurso FOR SHARE;
    IF v_estado <> 'proximo' THEN
        RAISE EXCEPTION 'No se pueden registrar participantes: el concurso ya esta %.', v_estado;
    END IF;
    IF v_limite IS NOT NULL
       AND (SELECT count(*) FROM participante WHERE id_concurso = NEW.id_concurso) >= v_limite THEN
        RAISE EXCEPTION 'Se alcanzo el limite de % participantes.', v_limite;
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_participante_validar
    BEFORE INSERT ON participante
    FOR EACH ROW EXECUTE FUNCTION fn_participante_validar();

-- ---- JUEZ: maximo de jueces activos (numero_jueces, tope 5) y nunca quedarse sin jueces activos (RF-02)
CREATE FUNCTION fn_juez_validar() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_tope    INTEGER;
    v_activos INTEGER;
BEGIN
    IF NEW.estado = 'activo' THEN
        SELECT COALESCE(numero_jueces, 5) INTO v_tope
          FROM concurso WHERE id_concurso = NEW.id_concurso FOR SHARE;
        SELECT count(*) INTO v_activos FROM juez
         WHERE id_concurso = NEW.id_concurso AND estado = 'activo' AND id_juez <> NEW.id_juez;
        IF v_activos + 1 > v_tope THEN
            RAISE EXCEPTION 'No se pueden tener mas de % jueces activos en este concurso.', v_tope;
        END IF;
    END IF;

    IF TG_OP = 'UPDATE' AND OLD.estado = 'activo' AND NEW.estado <> 'activo' THEN
        IF NOT EXISTS (SELECT 1 FROM juez
                        WHERE id_concurso = OLD.id_concurso AND estado = 'activo' AND id_juez <> OLD.id_juez) THEN
            RAISE EXCEPTION 'No se puede ocultar ni eliminar al ultimo juez activo.';
        END IF;
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_juez_validar
    BEFORE INSERT OR UPDATE OF estado, id_concurso ON juez
    FOR EACH ROW EXECUTE FUNCTION fn_juez_validar();

-- ---- TURNO: ronda, participante y palabra del mismo concurso; nivel de palabra = ronda;
--      al asignar la palabra se marca "usada" (RF-04, R-04)
CREATE FUNCTION fn_turno_validar() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_conc_ronda  INTEGER;
    v_num_ronda   SMALLINT;
    v_conc_part   INTEGER;
    v_estado_part VARCHAR(10);
    v_conc_pal    INTEGER;
    v_dif         VARCHAR(10);
    v_esperada    VARCHAR(10);
BEGIN
    SELECT id_concurso, numero_ronda INTO v_conc_ronda, v_num_ronda
      FROM ronda WHERE id_ronda = NEW.id_ronda;
    SELECT id_concurso, estado INTO v_conc_part, v_estado_part
      FROM participante WHERE id_participante = NEW.id_participante;
    SELECT id_concurso, dificultad INTO v_conc_pal, v_dif
      FROM palabra WHERE id_palabra = NEW.id_palabra;

    IF v_conc_part <> v_conc_ronda OR v_conc_pal <> v_conc_ronda THEN
        RAISE EXCEPTION 'La ronda, el participante y la palabra deben pertenecer al mismo concurso.';
    END IF;

    v_esperada := CASE v_num_ronda WHEN 1 THEN 'facil' WHEN 2 THEN 'intermedia' ELSE 'dificil' END;
    IF v_dif <> v_esperada THEN
        RAISE EXCEPTION 'La ronda % requiere palabras de nivel %, no %.', v_num_ronda, v_esperada, v_dif;
    END IF;

    IF TG_OP = 'INSERT' THEN
        IF v_estado_part <> 'activo' THEN
            RAISE EXCEPTION 'Un participante eliminado no puede tener turnos.';
        END IF;
        UPDATE palabra SET estado = 'usada' WHERE id_palabra = NEW.id_palabra;
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_turno_validar
    BEFORE INSERT OR UPDATE OF id_ronda, id_participante, id_palabra ON turno
    FOR EACH ROW EXECUTE FUNCTION fn_turno_validar();

-- ---- CALIFICACION: juez y turno del mismo concurso; el juez debe estar activo y el turno abierto (RF-08)
CREATE FUNCTION fn_calificacion_validar() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_conc_turno  INTEGER;
    v_estado_turno VARCHAR(10);
    v_conc_juez   INTEGER;
    v_estado_juez VARCHAR(10);
BEGIN
    SELECT r.id_concurso, t.estado INTO v_conc_turno, v_estado_turno
      FROM turno t JOIN ronda r ON r.id_ronda = t.id_ronda WHERE t.id_turno = NEW.id_turno;
    SELECT id_concurso, estado INTO v_conc_juez, v_estado_juez
      FROM juez WHERE id_juez = NEW.id_juez;

    IF v_conc_turno <> v_conc_juez THEN
        RAISE EXCEPTION 'El juez no pertenece al concurso de este turno.';
    END IF;
    IF TG_OP = 'INSERT' THEN
        IF v_estado_juez <> 'activo' THEN
            RAISE EXCEPTION 'Solo los jueces activos pueden calificar.';
        END IF;
        IF v_estado_turno <> 'abierto' THEN
            RAISE EXCEPTION 'Solo se puede calificar mientras el turno esta abierto.';
        END IF;
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_calificacion_validar
    BEFORE INSERT OR UPDATE OF id_turno, id_juez ON calificacion
    FOR EACH ROW EXECUTE FUNCTION fn_calificacion_validar();

-- ---- CALIFICACION: mantiene turno.puntaje_turno = suma de las calificaciones (RF-10)
CREATE FUNCTION fn_calificacion_recalcular() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_turno INTEGER;
BEGIN
    IF TG_OP = 'DELETE' THEN v_turno := OLD.id_turno; ELSE v_turno := NEW.id_turno; END IF;
    UPDATE turno
       SET puntaje_turno = COALESCE((SELECT sum(puntaje) FROM calificacion WHERE id_turno = v_turno), 0)
     WHERE id_turno = v_turno;
    RETURN NULL;
END $$;

CREATE TRIGGER trg_calificacion_recalcular
    AFTER INSERT OR UPDATE OF puntaje OR DELETE ON calificacion
    FOR EACH ROW EXECUTE FUNCTION fn_calificacion_recalcular();

-- ---- PARTICIPACION_RONDA: mismo concurso; en la ronda 3 nadie se elimina (RF-13)
CREATE FUNCTION fn_participacion_validar() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_conc_ronda INTEGER;
    v_num_ronda  SMALLINT;
    v_conc_part  INTEGER;
BEGIN
    SELECT id_concurso, numero_ronda INTO v_conc_ronda, v_num_ronda
      FROM ronda WHERE id_ronda = NEW.id_ronda;
    SELECT id_concurso INTO v_conc_part
      FROM participante WHERE id_participante = NEW.id_participante;

    IF v_conc_ronda <> v_conc_part THEN
        RAISE EXCEPTION 'La ronda y el participante deben pertenecer al mismo concurso.';
    END IF;
    IF v_num_ronda = 3 AND NEW.estado = 'eliminado' THEN
        RAISE EXCEPTION 'En la ronda 3 no se elimina a nadie: solo se definen los lugares 1, 2 y 3.';
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_participacion_validar
    BEFORE INSERT OR UPDATE OF id_ronda, id_participante, estado ON participacion_ronda
    FOR EACH ROW EXECUTE FUNCTION fn_participacion_validar();

-- ---- CARTA_PODIO: finalista del mismo concurso; una carta revelada no vuelve a ocultarse (RF-15)
CREATE FUNCTION fn_carta_validar() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF (SELECT id_concurso FROM participante WHERE id_participante = NEW.id_participante)
       <> NEW.id_concurso THEN
        RAISE EXCEPTION 'El finalista debe pertenecer al mismo concurso de la carta.';
    END IF;
    IF TG_OP = 'UPDATE' AND OLD.revelada AND NOT NEW.revelada THEN
        RAISE EXCEPTION 'Una carta revelada no puede volver a ocultarse.';
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_carta_validar
    BEFORE INSERT OR UPDATE ON carta_podio
    FOR EACH ROW EXECUTE FUNCTION fn_carta_validar();

COMMIT;