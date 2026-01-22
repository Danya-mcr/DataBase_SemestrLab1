--
-- PostgreSQL database dump
--


-- Dumped from database version 16.11 (Debian 16.11-1.pgdg13+1)
-- Dumped by pg_dump version 16.11 (Debian 16.11-1.pgdg13+1)

--
-- Name: checkinn(text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.checkinn(inn text) RETURNS boolean
    LANGUAGE plpgsql
    AS $_$
DECLARE
    len INT;
    m10 INT[] := ARRAY[2,4,10,3,5,9,4,6,8];
    m12 INT[] := ARRAY[7,2,4,10,3,5,9,4,6,8,3,7,2,4,10,3,5,9,4,6,8];
    sum INT := 0;
    i INT;
BEGIN

    len := LENGTH(inn);
    IF len NOT IN (10, 12) OR inn !~ '^[0-9]+$' THEN
        RETURN FALSE;
    END IF;
    
    IF len = 10 THEN
        FOR i IN 1..9 LOOP
            sum := sum + (SUBSTRING(inn, i, 1)::INT * m10[i]);
        END LOOP;
        RETURN (sum % 11 % 10) = SUBSTRING(inn, 10, 1)::INT;
    END IF;
    
    sum := 0;
    FOR i IN 1..10 LOOP
        sum := sum + (SUBSTRING(inn, i, 1)::INT * m12[i]);
    END LOOP;
    IF (sum % 11 % 10) != SUBSTRING(inn, 11, 1)::INT THEN
        RETURN FALSE;
    END IF;
    
    sum := 0;
    FOR i IN 1..11 LOOP
        sum := sum + (SUBSTRING(inn, i, 1)::INT * m12[i+10]);
    END LOOP;
    RETURN (sum % 11 % 10) = SUBSTRING(inn, 12, 1)::INT;
    
EXCEPTION WHEN OTHERS THEN
    RETURN FALSE;
END;
$_$;


ALTER FUNCTION public.checkinn(inn text) ;

--
-- Name: genprimarykey(text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.genprimarykey(tablename text) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
    seqName TEXT;
    nextVal BIGINT;
    numsBase62 TEXT := '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
    result TEXT := '';
    temp BIGINT;
    remainder INTEGER;
BEGIN
    seqName := 'seq_' || LOWER(REPLACE(TRIM(tableName), '_', ''));
    
    EXECUTE format('CREATE SEQUENCE IF NOT EXISTS %I', seqName);
    
    EXECUTE format('SELECT nextval(%L)', seqName) INTO nextVal;
    
    IF nextVal > POWER(62::NUMERIC, 5) THEN
        RAISE EXCEPTION 'Превышен лимит primarykey %', tableName;
    END IF;

	temp := nextVal;
	
    WHILE temp > 0 LOOP
        remainder := temp % 62;
        
        result := SUBSTRING(numsBase62 FROM remainder + 1 FOR 1) || result;
        
        temp := temp / 62;
    END LOOP;
    
    RETURN LPAD(result, 5, '0');
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Ошибка генерации primarykey %: %', tableName, SQLERRM;
END;
$$;


ALTER FUNCTION public.genprimarykey(tablename text) ;

--
-- Name: genregnumber(text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.genregnumber(tablename text) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
    seqName TEXT;
    nextVal BIGINT;
    currentYear TEXT;
BEGIN

    seqName := 'regnumber_' || LOWER(REPLACE(TRIM(tableName), '_', ''));
    
    EXECUTE format('CREATE SEQUENCE IF NOT EXISTS %I START 1', seqName);
    
    EXECUTE format('SELECT nextval(%L)', seqName) INTO nextVal;
    
    RETURN LPAD(nextVal::TEXT, 7, '0');
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Ошибка генерации regnumber %: %', tableName, SQLERRM;
END;
$$;


ALTER FUNCTION public.genregnumber(tablename text) ;

--
-- Name: getadmission(date, date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.getadmission(start_date date, end_date date) RETURNS TABLE(supplier_name text, product_name text, warehouse_name text, quantity integer)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        (s.lastname || ' ' || s.firstname || ' ' || s.patronymicname)::TEXT,
        p.name::TEXT,
        w.name::TEXT,
        SUM(m.count)::INTEGER
    FROM movement m
    JOIN basetable b ON m.basetable_id = b.id
    JOIN supplier s ON b.supplier_id = s.id
    JOIN product_org p ON m.product_id = p.id
    JOIN warehouse w ON m.warehouse_id = w.id
    JOIN documenttype dt ON b.documenttype_id = dt.id 
    WHERE m.type = '00001'
      AND dt.id IN ('00001', '00002')
      AND m.date BETWEEN start_date AND end_date
    GROUP BY s.lastname, s.firstname, s.patronymicname, p.name, w.name;
END;
$$;


ALTER FUNCTION public.getadmission(start_date date, end_date date) ;

--
-- Name: getcustomerstats(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.getcustomerstats() RETURNS TABLE(customer_name text, customer_inn text, total_invoices integer, total_amount integer, total_quantity integer, total_weight integer, avg_check numeric, last_purchase date)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        (c.lastname || ' ' || c.firstname || ' ' || COALESCE(c.patronymicname, ''))::TEXT,
        c.inn::TEXT,
        COUNT(DISTINCT b.id)::INTEGER,
        SUM(b.summ)::INTEGER,
        SUM(s.count)::INTEGER,
        SUM(s.brutto * s.count)::INTEGER,
        ROUND(AVG(b.summ)::NUMERIC, 2),
        MAX(b.date)::DATE
    FROM basetable b
    JOIN customer c ON b.customer_id = c.id
    JOIN salesinvoce si ON b.id = si.basetable_id
    JOIN salesinvoce_str s ON si.id = s.salesinvoce_id
    JOIN documenttype dt ON b.documenttype_id = dt.id
    WHERE dt.id = '00003' 
    GROUP BY c.id, c.lastname, c.firstname, c.patronymicname, c.inn
    ORDER BY SUM(b.summ) DESC;
END;
$$;


ALTER FUNCTION public.getcustomerstats() ;

--
-- Name: getproductbydate(date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.getproductbydate(check_date date) RETURNS TABLE(warehouse text, product text, stock integer)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        w.name::TEXT,
        p.name::TEXT,
        SUM(CASE WHEN m.type = '00001' THEN m.count ELSE -m.count END)::INTEGER
    FROM movement m
    JOIN warehouse w ON m.warehouse_id = w.id
    JOIN product_org p ON m.product_id = p.id
    WHERE m.date <= check_date
    GROUP BY w.name, p.name
    HAVING SUM(CASE WHEN m.type = '00001' THEN m.count ELSE -m.count END) > 0;
END;
$$;


ALTER FUNCTION public.getproductbydate(check_date date) ;

--
-- Name: getprofit(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.getprofit() RETURNS TABLE(product text, profit integer)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        COALESCE(p.product_name, s.product_name)::TEXT,
        (COALESCE(SUM(s.summ), 0) - COALESCE(SUM(p.summ), 0))::INTEGER
    FROM purchaseinvoce_str p
    FULL JOIN salesinvoce_str s ON p.product_id = s.product_id
    GROUP BY p.product_name, s.product_name
    ORDER BY COALESCE(p.product_name, s.product_name);
END;
$$;


ALTER FUNCTION public.getprofit() ;

--
-- Name: getsells(date, date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.getsells(start_date date, end_date date) RETURNS TABLE(customer_name text, product_name text, warehouse_name text, quantity integer)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        (s.lastname || ' ' || s.firstname || ' ' || s.patronymicname)::TEXT,
        p.name::TEXT,
        w.name::TEXT,
        SUM(m.count)::INTEGER
    FROM movement m
    JOIN basetable b ON m.basetable_id = b.id
    JOIN customer s ON b.customer_id = s.id
    JOIN product_org p ON m.product_id = p.id
    JOIN warehouse w ON m.warehouse_id = w.id
    JOIN documenttype dt ON b.documenttype_id = dt.id 
    WHERE m.type = '00002'
      AND dt.id IN ('00003')
      AND m.date BETWEEN start_date AND end_date
    GROUP BY s.lastname, s.firstname, s.patronymicname, p.name, w.name;
END;
$$;


ALTER FUNCTION public.getsells(start_date date, end_date date) ;

--
-- Name: trig_checkinn(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.trig_checkinn() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NOT checkInn(NEW.inn) THEN
        RAISE EXCEPTION 'Некорректный ИНН: %', NEW.inn;
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.trig_checkinn() ;

--
-- Name: trig_genprimarykey(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.trig_genprimarykey() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.id IS NULL THEN
        NEW.id := genprimarykey(TG_TABLE_NAME);
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.trig_genprimarykey() ;

--
-- Name: trig_genregnumber(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.trig_genregnumber() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.regnumber IS NULL THEN
        NEW.regnumber := genregnumber(TG_TABLE_NAME);
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.trig_genregnumber() ;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: basetable; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.basetable (
    id character varying(30) NOT NULL,
    customer_id character varying(100),
    supplier_id character varying(100),
    from_id character varying(30),
    corresponding_account character varying(100),
    date date,
    summ integer,
    documenttype_id character varying(30)
);


ALTER TABLE public.basetable ;

--
-- Name: customer; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.customer (
    id character varying(30) NOT NULL,
    organizationtype_id character varying(30),
    firstname character varying(50),
    lastname character varying(50),
    patronymicname character varying(50),
    phonenumber character varying(15),
    inn character varying(12)
);


ALTER TABLE public.customer ;

--
-- Name: documenttype; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.documenttype (
    id character varying(30) NOT NULL,
    type character varying(50)
);


ALTER TABLE public.documenttype ;

--
-- Name: movement; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.movement (
    id character varying(30) NOT NULL,
    warehouse_id character varying(30),
    product_id character varying(30),
    type character varying(30),
    date date,
    basetable_id character varying(30),
    count integer
);


ALTER TABLE public.movement ;

--
-- Name: movementtype; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.movementtype (
    id character varying(30) NOT NULL,
    type character varying(10)
);


ALTER TABLE public.movementtype ;

--
-- Name: organizationtype; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.organizationtype (
    id character varying(30) NOT NULL,
    type character varying(30)
);


ALTER TABLE public.organizationtype ;

--
-- Name: product_org; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.product_org (
    id character varying(30) NOT NULL,
    name character varying(100),
    weight_netto integer,
    weight_brutto integer,
    cost integer,
    unit_id character varying(30)
);


ALTER TABLE public.product_org ;

--
-- Name: purchaseinvoce; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.purchaseinvoce (
    id character varying(30) NOT NULL,
    basetable_id character varying(30),
    regnumber character varying(7)
);


ALTER TABLE public.purchaseinvoce ;

--
-- Name: purchaseinvoce_str; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.purchaseinvoce_str (
    id character varying(30) NOT NULL,
    purchaseinvoce_id character varying(30),
    product_id character varying(30),
    product_name character varying(100),
    unit_nameshort character varying(10),
    count integer,
    cost integer,
    summ integer
);


ALTER TABLE public.purchaseinvoce_str ;

--
-- Name: regnumber_purchaseinvoce; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.regnumber_purchaseinvoce
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.regnumber_purchaseinvoce ;

--
-- Name: regnumber_salesinvoce; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.regnumber_salesinvoce
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.regnumber_salesinvoce ;

--
-- Name: salesinvoce; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.salesinvoce (
    id character varying(30) NOT NULL,
    basetable_id character varying(30),
    regnumber character varying(7)
);


ALTER TABLE public.salesinvoce ;

--
-- Name: salesinvoce_str; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.salesinvoce_str (
    id character varying(30) NOT NULL,
    salesinvoce_id character varying(30),
    product_id character varying(30),
    product_name character varying(100),
    count integer,
    brutto integer,
    cost integer,
    summ integer
);


ALTER TABLE public.salesinvoce_str ;

--
-- Name: seq_basetable; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.seq_basetable
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.seq_basetable ;

--
-- Name: seq_customer; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.seq_customer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.seq_customer ;

--
-- Name: seq_documenttype; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.seq_documenttype
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.seq_documenttype ;

--
-- Name: seq_movement; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.seq_movement
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.seq_movement ;

--
-- Name: seq_movementtype; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.seq_movementtype
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.seq_movementtype ;

--
-- Name: seq_organizationtype; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.seq_organizationtype
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.seq_organizationtype ;

--
-- Name: seq_productorg; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.seq_productorg
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.seq_productorg ;

--
-- Name: seq_purchaseinvoce; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.seq_purchaseinvoce
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.seq_purchaseinvoce ;

--
-- Name: seq_purchaseinvocestr; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.seq_purchaseinvocestr
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.seq_purchaseinvocestr ;

--
-- Name: seq_salesinvoce; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.seq_salesinvoce
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.seq_salesinvoce ;

--
-- Name: seq_salesinvocestr; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.seq_salesinvocestr
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.seq_salesinvocestr ;

--
-- Name: seq_supplier; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.seq_supplier
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.seq_supplier ;

--
-- Name: seq_unit; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.seq_unit
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.seq_unit ;

--
-- Name: seq_warehouse; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.seq_warehouse
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.seq_warehouse ;

--
-- Name: stocktransfernote; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.stocktransfernote (
    id character varying(30) NOT NULL,
    basetable_id character varying(30),
    regnumber character varying(7)
);


ALTER TABLE public.stocktransfernote ;

--
-- Name: stocktransfernote_str; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.stocktransfernote_str (
    id character varying(30) NOT NULL,
    stocktransfernote_id character varying(30),
    product_id character varying(30),
    product_name character varying(100),
    unit_nameshort character varying(10),
    okei character varying(20),
    count_in_one_place integer,
    brutto integer,
    netto integer,
    product_cost integer,
    summ integer
);


ALTER TABLE public.stocktransfernote_str ;

--
-- Name: supplier; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.supplier (
    id character varying(30) NOT NULL,
    organizationtype_id character varying(30),
    firstname character varying(50),
    lastname character varying(50),
    patronymicname character varying(50),
    phonenumber character varying(15),
    inn character varying(12)
);


ALTER TABLE public.supplier ;

--
-- Name: unit; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.unit (
    id character varying(30) NOT NULL,
    name_full character varying(100),
    name_short character varying(10),
    name_inter character varying(50),
    okei character varying(20)
);


ALTER TABLE public.unit ;

--
-- Name: warehouse; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.warehouse (
    id character varying(30) NOT NULL,
    name character varying(100),
    address character varying(100),
    city character varying(100)
);


ALTER TABLE public.warehouse ;

--
-- Data for Name: basetable; Type: TABLE DATA; Schema: public; Owner: postgres
--

-- Data for Name: basetable
INSERT INTO public.basetable (id, customer_id, supplier_id, from_id, corresponding_account, date, summ, documenttype_id) VALUES
('00004', '00002', NULL, NULL, NULL, '2025-01-02', NULL, '00003'),
('00003', '00001', NULL, NULL, NULL, '2025-01-02', '144500', '00003'),
('00001', NULL, '00001', NULL, 'check_34567890', '2025-01-01', '40000', '00001'),
('00002', NULL, '00002', NULL, 'check_4357785', '2025-01-02', '56000', '00001');

-- Data for Name: customer
INSERT INTO public.customer (id, organizationtype_id, firstname, lastname, patronymicname, phonenumber, inn) VALUES
('00001', '00002', 'Александра', 'Соколова', 'Викторовна', '+74958889900', '108618833348'),
('00002', '00003', 'Иван', 'Петров', 'Сергеевич', '+79161234567', '804136311683'),
('00003', '00004', 'Мария', 'Сидорова', 'Александровна', '+79162345678', '352835255404'),
('00004', '00003', 'Алексей', 'Иванов', 'Петрович', '+79163456789', '536956827744'),
('00005', '00004', 'Елена', 'Кузнецова', 'Владимировна', '+79164567890', '753089264159'),
('00006', '00003', 'Дмитрий', 'Смирнов', 'Андреевич', '+79165678901', '418108907290'),
('00007', '00002', 'Александр', 'Иванов', 'Сергеевич', '+74951234567', '923913428046'),
('00008', '00002', 'Елена', 'Петрова', 'Андреевна', '+74952223344', '373413518434'),
('00009', '00002', 'Михаил', 'Сидоров', 'Игоревич', '+74953334455', '280824809163'),
('0000A', '00002', 'Ольга', 'Кузнецова', 'Владимировна', '+78121234567', '623941208252'),
('0000B', '00002', 'Дмитрий', 'Смирнов', 'Алексеевич', '+74954445566', '653064662765'),
('0000C', '00002', 'Анна', 'Федорова', 'Павловна', '+74955556677', '357019115537'),
('0000D', '00002', 'Алексей', 'Попов', 'Николаевич', '+74956667788', '792271239603'),
('0000E', '00002', 'Мария', 'Васильева', 'Дмитриевна', '+78122468010', '677692346851'),
('0000F', '00002', 'Иван', 'Морозов', 'Петрович', '+74957778899', '195382140983');

-- Data for Name: documenttype
INSERT INTO public.documenttype (id, type) VALUES
('00001', 'purchaseinvoce'),
('00002', 'stocktransfernote'),
('00003', 'salesinvoce');

-- Data for Name: movement
INSERT INTO public.movement (id, warehouse_id, product_id, type, date, basetable_id, count) VALUES
('00005', '00001', '00005', '00001', '2025-01-06', NULL, '300'),
('00006', '00002', '00004', '00002', '2025-01-07', NULL, '400'),
('00007', '00003', '00001', '00001', '2025-01-07', NULL, '350'),
('00002', '00002', '00004', '00001', '2025-01-05', '00002', '1400'),
('00001', '00001', '00005', '00001', '2025-01-05', '00001', '500'),
('00003', '00001', '00005', '00002', '2025-01-05', '00003', '50'),
('00004', '00002', '00004', '00002', '2025-01-06', '00003', '200');

-- Data for Name: movementtype
INSERT INTO public.movementtype (id, type) VALUES
('00001', 'in'),
('00002', 'out');

-- Data for Name: organizationtype
INSERT INTO public.organizationtype (id, type) VALUES
('00002', 'ООО'),
('00003', 'ИП'),
('00004', 'Самозанятый');

-- Data for Name: product_org
INSERT INTO public.product_org (id, name, weight_netto, weight_brutto, cost, unit_id) VALUES
('00001', 'Жевательная резинка', '1500', '2200', '50', '00001'),
('00002', 'Торт медовик', '170', '250', '2500', '00001'),
('00003', 'Торт наполеон', '180', '220', '1500', '00001'),
('00004', 'Докторская колбаса', '850', '950', '800', '00001'),
('00005', 'Сахар', '1000', '1050', '85', '00002'),
('00006', 'Картофель', '2000', '2100', '45', '00002'),
('00007', 'Мясо говяжье', '1000', '1050', '450', '00002'),
('00008', 'Яблоки', '1500', '1600', '120', '00002'),
('00009', 'Рис', '250', '300', '420', '00002'),
('0000A', 'Молоко', '950', '1000', '75', '00003'),
('0000B', 'Вода', '1000', '1050', '40', '00003'),
('0000C', 'Масло подсолнечное', '900', '1000', '150', '00003'),
('0000D', 'Соевый соус', '1000', '1000', '55', '00003'),
('0000E', 'Сок апельсиновый', '1000', '1100', '120', '00003');

-- Data for Name: purchaseinvoce
INSERT INTO public.purchaseinvoce (id, basetable_id, regnumber) VALUES
('00001', '00001', '0000001'),
('00002', '00002', '0000002');

-- Data for Name: purchaseinvoce_str
INSERT INTO public.purchaseinvoce_str (id, purchaseinvoce_id, product_id, product_name, unit_nameshort, count, cost, summ) VALUES
('00001', '00001', '00005', 'Сахар', NULL, '500', '80', '40000'),
('00002', '00002', '00004', 'Докторская колбаса', NULL, '1400', '40', '56000');

-- Data for Name: salesinvoce
INSERT INTO public.salesinvoce (id, basetable_id, regnumber) VALUES
('00001', '00003', '0000001');

-- Data for Name: salesinvoce_str
INSERT INTO public.salesinvoce_str (id, salesinvoce_id, product_id, product_name, count, brutto, cost, summ) VALUES
('00001', '00001', '00005', 'Сахар', '50', NULL, '90', '4500'),
('00002', '00001', '00004', 'Докторская колбаса', '200', NULL, '700', '140000');

-- Data for Name: stocktransfernote
-- Таблица пустая, INSERT не нужен

-- Data for Name: stocktransfernote_str
-- Таблица пустая, INSERT не нужен

-- Data for Name: supplier
INSERT INTO public.supplier (id, organizationtype_id, firstname, lastname, patronymicname, phonenumber, inn) VALUES
('00001', '00003', 'Антон', 'Волков', 'Викторович', '+79161112233', '176122593123'),
('00002', '00004', 'Светлана', 'Орлова', 'Ивановна', '+79162223344', '199326325057'),
('00003', '00003', 'Павел', 'Белов', 'Семенович', '+79163334455', '611341384739'),
('00004', '00004', 'Наталья', 'Григорьева', 'Анатольевна', '+79164445566', '323216487591'),
('00005', '00003', 'Владимир', 'Козлов', 'Олегович', '+79165556677', '157965792509'),
('00006', '00002', 'Артем', 'Лебедев', 'Романович', '+74951112233', '388555678502'),
('00007', '00002', 'Юлия', 'Семенова', 'Аркадьевна', '+74952223344', '459847769583'),
('00008', '00002', 'Константин', 'Егоров', 'Валерьевич', '+74953334455', '930186808891'),
('00009', '00002', 'Екатерина', 'Павлова', 'Степановна', '+78121112233', '061886578858'),
('0000A', '00002', 'Роман', 'Комаров', 'Геннадьевич', '+74954445566', '700844093603'),
('0000B', '00002', 'Оксана', 'Ильина', 'Борисовна', '+74955556677', '401523395300'),
('0000C', '00002', 'Станислав', 'Максимов', 'Федорович', '+74956667788', '253273704425'),
('0000D', '00002', 'Лариса', 'Захарова', 'Юрьевна', '+78122445566', '831766765506'),
('0000E', '00002', 'Георгий', 'Соловьев', 'Анатольевич', '+74957778899', '222572100607');

-- Data for Name: unit
INSERT INTO public.unit (id, name_full, name_short, name_inter, okei) VALUES
('00001', 'Штука', 'Шт', 'Piece', '796'),
('00002', 'Килограмм', 'Кг', 'Kilogram', '166'),
('00003', 'Литр', 'Л', 'Liter', '112');

-- Data for Name: warehouse
INSERT INTO public.warehouse (id, name, address, city) VALUES
('00001', 'Центральный склад', 'ул. Ленина, д. 15', 'Москва'),
('00002', 'Северный склад', 'пр. Победы, д. 42', 'Санкт-Петербург'),
('00003', 'Южный логистический центр', 'ул. Садовая, д. 8', 'Краснодар'),
('00004', 'Восточный склад', 'ул. Заводская, д. 3', 'Екатеринбург'),
('00005', 'Западный распределитель', 'ул. Мира, д. 25', 'Калининград'),
('00006', 'Склад №1', 'ул. Техническая, д. 1', 'Казань'),
('00007', 'Холодильный комплекс', 'ул. Холодильная, д. 7', 'Новосибирск'),
('00008', 'Склад быстрой доставки', 'ул. Транспортная, д. 12', 'Ростов-на-Дону'),
('00009', 'Мегаполис-Склад', 'ул. Мегаполисная, д. 99', 'Нижний Новгород'),
('0000A', 'Авангард Логистикс', 'ул. Промышленная, д. 33', 'Самара');


--
-- Name: regnumber_purchaseinvoce; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.regnumber_purchaseinvoce', 2, true);


--
-- Name: regnumber_salesinvoce; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.regnumber_salesinvoce', 1, true);


--
-- Name: seq_basetable; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.seq_basetable', 4, true);


--
-- Name: seq_customer; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.seq_customer', 16, true);


--
-- Name: seq_documenttype; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.seq_documenttype', 4, true);


--
-- Name: seq_movement; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.seq_movement', 7, true);


--
-- Name: seq_movementtype; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.seq_movementtype', 2, true);


--
-- Name: seq_organizationtype; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.seq_organizationtype', 4, true);


--
-- Name: seq_productorg; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.seq_productorg', 14, true);


--
-- Name: seq_purchaseinvoce; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.seq_purchaseinvoce', 2, true);


--
-- Name: seq_purchaseinvocestr; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.seq_purchaseinvocestr', 2, true);


--
-- Name: seq_salesinvoce; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.seq_salesinvoce', 1, true);


--
-- Name: seq_salesinvocestr; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.seq_salesinvocestr', 2, true);


--
-- Name: seq_supplier; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.seq_supplier', 14, true);


--
-- Name: seq_unit; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.seq_unit', 3, true);


--
-- Name: seq_warehouse; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.seq_warehouse', 10, true);


--
-- Name: basetable basetable_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.basetable
    ADD CONSTRAINT basetable_pkey PRIMARY KEY (id);


--
-- Name: customer customer_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.customer
    ADD CONSTRAINT customer_pkey PRIMARY KEY (id);


--
-- Name: documenttype documenttype_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.documenttype
    ADD CONSTRAINT documenttype_pkey PRIMARY KEY (id);


--
-- Name: movement movement_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.movement
    ADD CONSTRAINT movement_pkey PRIMARY KEY (id);


--
-- Name: movementtype movementtype_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.movementtype
    ADD CONSTRAINT movementtype_pkey PRIMARY KEY (id);


--
-- Name: organizationtype organizationtype_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.organizationtype
    ADD CONSTRAINT organizationtype_pkey PRIMARY KEY (id);


--
-- Name: unit product_org_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.unit
    ADD CONSTRAINT product_org_pkey PRIMARY KEY (id);


--
-- Name: product_org product_org_pkey1; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.product_org
    ADD CONSTRAINT product_org_pkey1 PRIMARY KEY (id);


--
-- Name: purchaseinvoce purchaseinvoce_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchaseinvoce
    ADD CONSTRAINT purchaseinvoce_pkey PRIMARY KEY (id);


--
-- Name: purchaseinvoce_str purchaseinvoce_str_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchaseinvoce_str
    ADD CONSTRAINT purchaseinvoce_str_pkey PRIMARY KEY (id);


--
-- Name: salesinvoce salesinvoce_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.salesinvoce
    ADD CONSTRAINT salesinvoce_pkey PRIMARY KEY (id);


--
-- Name: salesinvoce_str salesinvoce_str_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.salesinvoce_str
    ADD CONSTRAINT salesinvoce_str_pkey PRIMARY KEY (id);


--
-- Name: stocktransfernote stocktransfernote_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stocktransfernote
    ADD CONSTRAINT stocktransfernote_pkey PRIMARY KEY (id);


--
-- Name: stocktransfernote_str stocktransfernote_str_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stocktransfernote_str
    ADD CONSTRAINT stocktransfernote_str_pkey PRIMARY KEY (id);


--
-- Name: supplier supplier_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.supplier
    ADD CONSTRAINT supplier_pkey PRIMARY KEY (id);


--
-- Name: warehouse warehouse_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.warehouse
    ADD CONSTRAINT warehouse_pkey PRIMARY KEY (id);


--
-- Name: basetable baseTable_trig_pk; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER "baseTable_trig_pk" BEFORE INSERT ON public.basetable FOR EACH ROW EXECUTE FUNCTION public.trig_genprimarykey();


--
-- Name: customer customer_trig_inn; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER customer_trig_inn BEFORE INSERT ON public.customer FOR EACH ROW EXECUTE FUNCTION public.trig_checkinn();


--
-- Name: customer customer_trig_pk; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER customer_trig_pk BEFORE INSERT ON public.customer FOR EACH ROW EXECUTE FUNCTION public.trig_genprimarykey();


--
-- Name: documenttype documentRype_trig_pk; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER "documentRype_trig_pk" BEFORE INSERT ON public.documenttype FOR EACH ROW EXECUTE FUNCTION public.trig_genprimarykey();


--
-- Name: movementtype movementType_trig_pk; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER "movementType_trig_pk" BEFORE INSERT ON public.movementtype FOR EACH ROW EXECUTE FUNCTION public.trig_genprimarykey();


--
-- Name: movement movement_trig_pk; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER movement_trig_pk BEFORE INSERT ON public.movement FOR EACH ROW EXECUTE FUNCTION public.trig_genprimarykey();


--
-- Name: organizationtype organizationType_trig_pk; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER "organizationType_trig_pk" BEFORE INSERT ON public.organizationtype FOR EACH ROW EXECUTE FUNCTION public.trig_genprimarykey();


--
-- Name: product_org product_trig_pk; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER product_trig_pk BEFORE INSERT ON public.product_org FOR EACH ROW EXECUTE FUNCTION public.trig_genprimarykey();


--
-- Name: purchaseinvoce purchaseInvoce_trig_pk; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER "purchaseInvoce_trig_pk" BEFORE INSERT ON public.purchaseinvoce FOR EACH ROW EXECUTE FUNCTION public.trig_genprimarykey();


--
-- Name: purchaseinvoce purchaseInvoce_trig_regNumber; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER "purchaseInvoce_trig_regNumber" BEFORE INSERT ON public.purchaseinvoce FOR EACH ROW EXECUTE FUNCTION public.trig_genregnumber();


--
-- Name: purchaseinvoce_str purchesInvoseStr_trig_pk; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER "purchesInvoseStr_trig_pk" BEFORE INSERT ON public.purchaseinvoce_str FOR EACH ROW EXECUTE FUNCTION public.trig_genprimarykey();


--
-- Name: salesinvoce_str salesInvoceStr_trig_pk; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER "salesInvoceStr_trig_pk" BEFORE INSERT ON public.salesinvoce_str FOR EACH ROW EXECUTE FUNCTION public.trig_genprimarykey();


--
-- Name: salesinvoce salesInvoce_trig_pk; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER "salesInvoce_trig_pk" BEFORE INSERT ON public.salesinvoce FOR EACH ROW EXECUTE FUNCTION public.trig_genprimarykey();


--
-- Name: salesinvoce selesInvoce_trig_regNumber; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER "selesInvoce_trig_regNumber" BEFORE INSERT ON public.salesinvoce FOR EACH ROW EXECUTE FUNCTION public.trig_genregnumber();


--
-- Name: stocktransfernote_str stockTransferNoteStr_trig_pk; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER "stockTransferNoteStr_trig_pk" BEFORE INSERT ON public.stocktransfernote_str FOR EACH ROW EXECUTE FUNCTION public.trig_genprimarykey();


--
-- Name: stocktransfernote stockTransferNote_trig_pk; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER "stockTransferNote_trig_pk" BEFORE INSERT ON public.stocktransfernote FOR EACH ROW EXECUTE FUNCTION public.trig_genprimarykey();


--
-- Name: stocktransfernote stocktransfernote_trig_regNumber; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER "stocktransfernote_trig_regNumber" BEFORE INSERT ON public.stocktransfernote FOR EACH ROW EXECUTE FUNCTION public.trig_genregnumber();


--
-- Name: supplier supplier_trig_inn; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER supplier_trig_inn BEFORE INSERT ON public.supplier FOR EACH ROW EXECUTE FUNCTION public.trig_checkinn();


--
-- Name: supplier supplier_trig_pk; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER supplier_trig_pk BEFORE INSERT ON public.supplier FOR EACH ROW EXECUTE FUNCTION public.trig_genprimarykey();


--
-- Name: unit unit_trig_pk; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER unit_trig_pk BEFORE INSERT ON public.unit FOR EACH ROW EXECUTE FUNCTION public.trig_genprimarykey();


--
-- Name: warehouse warehouse_trig_pk; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER warehouse_trig_pk BEFORE INSERT ON public.warehouse FOR EACH ROW EXECUTE FUNCTION public.trig_genprimarykey();


--
-- Name: basetable basetable_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.basetable
    ADD CONSTRAINT basetable_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customer(id);


--
-- Name: basetable basetable_documenttype_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.basetable
    ADD CONSTRAINT basetable_documenttype_id_fkey FOREIGN KEY (documenttype_id) REFERENCES public.documenttype(id);


--
-- Name: basetable basetable_from_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.basetable
    ADD CONSTRAINT basetable_from_id_fkey FOREIGN KEY (from_id) REFERENCES public.warehouse(id);


--
-- Name: basetable basetable_supplier_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.basetable
    ADD CONSTRAINT basetable_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES public.supplier(id);


--
-- Name: customer customer_organizationtype_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.customer
    ADD CONSTRAINT customer_organizationtype_id_fkey FOREIGN KEY (organizationtype_id) REFERENCES public.organizationtype(id);


--
-- Name: movement movement_basetable_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.movement
    ADD CONSTRAINT movement_basetable_id_fkey FOREIGN KEY (basetable_id) REFERENCES public.basetable(id);


--
-- Name: movement movement_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.movement
    ADD CONSTRAINT movement_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.product_org(id);


--
-- Name: movement movement_type_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.movement
    ADD CONSTRAINT movement_type_fkey FOREIGN KEY (type) REFERENCES public.movementtype(id);


--
-- Name: movement movement_warehouse_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.movement
    ADD CONSTRAINT movement_warehouse_id_fkey FOREIGN KEY (warehouse_id) REFERENCES public.warehouse(id);


--
-- Name: product_org product_org_unit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.product_org
    ADD CONSTRAINT product_org_unit_id_fkey FOREIGN KEY (unit_id) REFERENCES public.unit(id);


--
-- Name: purchaseinvoce purchaseinvoce_basetable_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchaseinvoce
    ADD CONSTRAINT purchaseinvoce_basetable_id_fkey FOREIGN KEY (basetable_id) REFERENCES public.basetable(id);


--
-- Name: purchaseinvoce_str purchaseinvoce_str_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchaseinvoce_str
    ADD CONSTRAINT purchaseinvoce_str_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.product_org(id);


--
-- Name: purchaseinvoce_str purchaseinvoce_str_purchaseinvoce_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchaseinvoce_str
    ADD CONSTRAINT purchaseinvoce_str_purchaseinvoce_id_fkey FOREIGN KEY (purchaseinvoce_id) REFERENCES public.purchaseinvoce(id);


--
-- Name: salesinvoce salesinvoce_basetable_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.salesinvoce
    ADD CONSTRAINT salesinvoce_basetable_id_fkey FOREIGN KEY (basetable_id) REFERENCES public.basetable(id);


--
-- Name: salesinvoce_str salesinvoce_str_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.salesinvoce_str
    ADD CONSTRAINT salesinvoce_str_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.product_org(id);


--
-- Name: salesinvoce_str salesinvoce_str_salesinvoce_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.salesinvoce_str
    ADD CONSTRAINT salesinvoce_str_salesinvoce_id_fkey FOREIGN KEY (salesinvoce_id) REFERENCES public.salesinvoce(id);


--
-- Name: stocktransfernote stocktransfernote_basetable_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stocktransfernote
    ADD CONSTRAINT stocktransfernote_basetable_id_fkey FOREIGN KEY (basetable_id) REFERENCES public.basetable(id);


--
-- Name: stocktransfernote_str stocktransfernote_str_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stocktransfernote_str
    ADD CONSTRAINT stocktransfernote_str_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.product_org(id);


--
-- Name: stocktransfernote_str stocktransfernote_str_stocktransfernote_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stocktransfernote_str
    ADD CONSTRAINT stocktransfernote_str_stocktransfernote_id_fkey FOREIGN KEY (stocktransfernote_id) REFERENCES public.stocktransfernote(id);


--
-- Name: supplier supplier_organizationtype_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.supplier
    ADD CONSTRAINT supplier_organizationtype_id_fkey FOREIGN KEY (organizationtype_id) REFERENCES public.organizationtype(id);


--
-- PostgreSQL database dump complete
--


