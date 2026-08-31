#=====================================================================================
# 
# Project goal: to create a table with the distribution of affiliations to the social 
# security per group of river basin (river basin system)
#
#=====================================================================================
library(tidyverse)

getwd()

setwd("C:/Users/Proprietário/Documents/PERSONAL/ESPAÑA/Trabajo con Angels/Datos")


#===================================================================================
#Funtion to clean and organize population table into a single one and for 2021 only
#===================================================================================

limpiar_poblacion <- function(archivo) {
  
  datos <- read_csv2(
    archivo,
    locale = locale(encoding = "Latin1"),
    col_types = cols(.default = col_character())
  )
  
  datos %>%
    filter(
      Sexo == "Total",
      Periodo == "2021"
    ) %>%
    separate(
      Municipios,
      into = c("CODIMUNI", "NOMMUNI"),
      sep = " ",
      extra = "merge"
    ) %>%
    mutate(
      POBLACION = parse_number(
        Total,
        locale = locale(
          grouping_mark = ".",
          decimal_mark = ","
        )
      )
    ) %>%
    select(
      CODIMUNI,
      NOMMUNI,
      POBLACION
    )
}

#========================================================================
#Aply the function to the 4 files with 4 different provinces of Catalonia

pob_barcelona_2021 <- limpiar_poblacion("Demograficos y economicos/Poblacion/Poblacion-mun-barcelona.csv")

pob_girona_2021 <- limpiar_poblacion("Demograficos y economicos/Poblacion/Poblacion-mun-girona.csv")

pob_lleida_2021 <- limpiar_poblacion("Demograficos y economicos/Poblacion/Poblacion-mun-lleida.csv")

pob_tarragona_2021 <- limpiar_poblacion("Demograficos y economicos/Poblacion/Poblacion-mun-tarragona.csv")

#===============================================================
#Join into a single table
population_2021 <- bind_rows(
  pob_barcelona_2021,
  pob_girona_2021,
  pob_lleida_2021,
  pob_tarragona_2021
)

#Check there are no duplicate municipality codes
population_2021 %>%
  count(CODIMUNI) %>%
  filter(n > 1)

nrow(population_2021)
summary(population_2021$POBLACION)

#The max looks too high. Check which municipalities have the largest population
population_2021 %>%
  arrange(desc(POBLACION)) %>%
  head(10)

#In the data they also include the total per Province (2-character code). 
#We do not need that.
#Filter any code that is not 5-characters long.
population_2021 <- population_2021 %>%
  filter(nchar(CODIMUNI) == 5)

nrow(population_2021)

#=============================================================================
# 
#  PART I: Loading municipality shapefile and add population data to it
#
#=============================================================================

library(sf)

municipios <- st_read(
  "QGIS/Divisiones administrativas 2/divisions-administratives-v2r2-municipis-250000-20260120.shp"
)

names(municipios)

head(municipios)

nrow(municipios)

municipios %>%
  st_drop_geometry() %>%
  select(CODIMUNI, NOMMUNI, CODICOMAR, NOMCOMAR) %>%
  head(10)

#Check Shapefile municipality codes
municipios %>%
  st_drop_geometry() %>%
  select(CODIMUNI, NOMMUNI, CODICOMAR, NOMCOMAR) %>%
  head(10)

municipios %>%
  st_drop_geometry() %>%
  mutate(n_digitos = nchar(CODIMUNI)) %>%
  count(n_digitos)

#The codes are in the 6-digit format, while in the population data it is 5-digits code
#add a column with only first 5 digits
municipios <- municipios %>%
  mutate(CODIMUNI_5 = substr(CODIMUNI, 1, 5))

#Check which municipalities are in one table and not in the other
municipios %>%
  st_drop_geometry() %>%
  anti_join(
    population_2021,
    by = c("CODIMUNI_5" = "CODIMUNI")
  ) %>%
  select(CODIMUNI, CODIMUNI_5, NOMMUNI, NOMCOMAR)

population_2021 %>%
  anti_join(
    municipios %>% st_drop_geometry(),
    by = c("CODIMUNI" = "CODIMUNI_5")
  )

#Perform left join between municipios and population table
municipios <- municipios %>%
  left_join(
    population_2021,
    by = c("CODIMUNI_5" = "CODIMUNI")
  )

names(municipios)

head(municipios)

nrow(municipios)

municipios <- municipios %>%
  select(-NOMMUNI.y) %>%
  rename(NOMMUNI = NOMMUNI.x)

names(municipios)

#======================================================================================
#
#  PART II: Intersect the river basins shapefile with municipalities
#
#======================================================================================

AGUA_CUENCA_SISTEMA <- st_read(
  "QGIS/Cuencas2/AGUA_CUENCA_SISTEMA.gpkg"
)

names(AGUA_CUENCA_SISTEMA)

#The column "Grupo" includes the 5 river basin systems we will work with
unique(AGUA_CUENCA_SISTEMA$GRUPO)

#Rename the group "Ter-Llobregat", it is the official name.
AGUA_CUENCA_SISTEMA <- AGUA_CUENCA_SISTEMA %>%
  mutate(
    GRUPO = if_else(GRUPO == "Ter-Llobre", "Ter-Llobregat", GRUPO)
  )

#Check that both our shapefiles (municipalities and river basins) have the same coordenates
st_crs(municipios)

st_crs(AGUA_CUENCA_SISTEMA)

nrow(AGUA_CUENCA_SISTEMA)

#Intersection between municipalities and the river basins
municipio_cuenca <- st_intersection(
  municipios,
  AGUA_CUENCA_SISTEMA
)

# Create one row per municipality + system
municipio_sistema <- municipio_cuenca %>%
  mutate(
    area_interseccion = st_area(geometry)
  ) %>%
  st_drop_geometry() %>%
  group_by(
    CODIMUNI,
    NOMMUNI,
    CODICOMAR,
    NOMCOMAR,
    POBLACION,
    GRUPO
  ) %>%
  summarise(
    area_sistema = sum(area_interseccion),
    .groups = "drop"
  )

# ============================================================
# MUNICIPALITY → SYSTEM SPATIAL WEIGHTS
# ============================================================

# Calculate total area of each municipality
# and its share within each system
municipio_sistema <- municipio_sistema %>%
  group_by(CODIMUNI) %>%
  mutate(
    area_total_municipio = sum(area_sistema),
    peso_superficie = area_sistema / area_total_municipio
  ) %>%
  ungroup()

# Check that weights add up to 1 for each municipality
municipio_sistema %>%
  group_by(CODIMUNI) %>%
  summarise(
    suma_pesos = sum(peso_superficie),
    .groups = "drop"
  ) %>%
  summarise(
    minimo = min(suma_pesos),
    maximo = max(suma_pesos)
  )

# ============================================================
# ASSIGNED POPULATION
# ============================================================

# Assign municipality population to each system
# according to the municipality's territorial share
municipio_sistema <- municipio_sistema %>%
  mutate(
    poblacion_asignada = POBLACION * peso_superficie
  )


#===========================================================================
# Exploration of the municipality/system sections
#===========================================================================

#Which municipalities are divided in between more than one system
municipio_sistema %>%
  distinct(CODIMUNI, GRUPO) %>%
  count(CODIMUNI) %>%
  filter(n > 1)

municipio_sistema %>%
  distinct(
    CODIMUNI,
    NOMMUNI,
    CODICOMAR,
    NOMCOMAR,
    GRUPO
  ) %>%
  group_by(
    CODIMUNI,
    NOMMUNI,
    CODICOMAR,
    NOMCOMAR
  ) %>%
  filter(n() > 1) %>%
  arrange(CODICOMAR, NOMMUNI)

#How many?
municipio_sistema %>%
  distinct(CODIMUNI, GRUPO) %>%
  count(CODIMUNI) %>%
  filter(n > 1) %>%
  summarise(
    municipios_divididos = n()
  )

# 138 municipalities are intersected by more than one river basin system.
# This represents approximately 14.6% of all municipalities.
# Most are located across 2 systems; only 5 are associated with 3 systems.

#=============================================================================
# 
#  PART III: Distribution of population by Comarca and system
#
#=============================================================================

# Check municipality-level data
municipio_sistema %>%
  select(
    CODIMUNI,
    NOMMUNI,
    CODICOMAR,
    NOMCOMAR,
    GRUPO,
    POBLACION,
    peso_superficie,
    poblacion_asignada
  ) %>%
  head(10)

#=============================================================================
# AGGREGATE ASSIGNED POPULATION: MUNICIPALITY → COMARCA + SYSTEM
#=============================================================================

# Group municipalities belonging to the same comarca and management system.
# The assigned population of municipalities is aggregated to obtain
# the population of each comarca within each management system.

comarca_sistema_poblacion <- municipio_sistema %>%
  group_by(
    CODICOMAR,
    NOMCOMAR,
    GRUPO
  ) %>%
  summarise(
    poblacion_sistema = sum(poblacion_asignada, na.rm = TRUE),
    .groups = "drop"
  )

# Population weigh by district/system

# Calculate the share of each management system within each comarca.

comarca_sistema_poblacion <- comarca_sistema_poblacion %>%
  group_by(CODICOMAR) %>%
  mutate(
    peso_poblacion = poblacion_sistema / sum(poblacion_sistema)
  ) %>%
  ungroup()


#Checks
# The population weights should sum to 1 for every comarca.

comarca_sistema_poblacion %>%
  group_by(CODICOMAR) %>%
  summarise(
    suma_peso = sum(peso_poblacion),
    .groups = "drop"
  ) %>%
  summarise(
    minimo = min(suma_peso),
    maximo = max(suma_peso)
  )

# View some comarcas
comarca_sistema_poblacion %>%
  arrange(CODICOMAR, desc(peso_poblacion)) %>%
  head(20)


#=============================================================================
#
# PART IV: Integrating the affiliations data
#
#=============================================================================
library(readxl)

afiliaciones <- read_excel("Output/afiliaciones_totales_comarcas.xlsx")

names(afiliaciones)
nrow(afiliaciones)
head(afiliaciones, 10)

unique(afiliaciones$sector)

afiliaciones %>%
  count(sector) %>%
  arrange(desc(n))

afiliaciones %>%
  head(15)

#Ver si hay la misma cantidad de comarcas
unique(afiliaciones$comarca)
unique(municipio_sistema$NOMCOMAR)

n_distinct(afiliaciones$comarca)
n_distinct(municipio_sistema$NOMCOMAR)

#Cambiar nombre de Aran
afiliaciones <- afiliaciones %>%
  mutate(
    comarca = if_else(
      comarca == "Aran",
      "Val d'Aran",
      comarca
    )
  )

#Ver que todos los nombres coinciden
setdiff(
  unique(afiliaciones$comarca),
  unique(municipio_sistema$NOMCOMAR)
)

setdiff(
  unique(municipio_sistema$NOMCOMAR),
  unique(afiliaciones$comarca)
)

#Pasar formato de wide a long
afiliaciones_largo <- afiliaciones %>%
  pivot_longer(
    cols = starts_with("af_"),
    names_to = "año",
    names_prefix = "af_",
    values_to = "afiliaciones"
  )

nrow(afiliaciones_largo)

afiliaciones_largo %>%
  head(10)
#=============================================================================
#  AFILIACIONES POR SISTEMA DE GESTIÓN
#=============================================================================
#Left join with affiliations and district data and distribution of the data 

afiliaciones_sistema <- afiliaciones_largo %>%
  left_join(
    comarca_sistema_poblacion %>%
      select(NOMCOMAR, GRUPO, peso_poblacion) %>%
      mutate(
        peso_poblacion = as.numeric(peso_poblacion)
      ),
    by = c("comarca" = "NOMCOMAR")
  ) %>%
  mutate(
    afiliaciones_asignadas = afiliaciones * peso_poblacion
  )

#Checks

# Check that assigned affiliations reproduce the original total
# for each sector, comarca and year
afiliaciones_sistema %>%
  filter(!is.na(afiliaciones)) %>%
  group_by(sector, comarca, año) %>%
  summarise(
    afiliaciones_original = first(afiliaciones),
    afiliaciones_asignadas = sum(afiliaciones_asignadas, na.rm = TRUE),
    diferencia = afiliaciones_asignadas - afiliaciones_original,
    .groups = "drop"
  ) %>%
  summarise(
    max_diferencia = max(abs(diferencia))
  )


# Check for missing values
afiliaciones_sistema %>%
  summarise(
    na_afiliaciones = sum(is.na(afiliaciones)),
    na_peso = sum(is.na(peso_poblacion)),
    na_asignadas = sum(is.na(afiliaciones_asignadas))
  )

# Show observations with missing values
afiliaciones_sistema %>%
  filter(
    is.na(afiliaciones) |
      is.na(peso_poblacion) |
      is.na(afiliaciones_asignadas)
  ) %>%
  select(
    sector,
    comarca,
    año,
    afiliaciones,
    peso_poblacion,
    afiliaciones_asignadas
  ) %>%
  head(20)


# Check that all 5 management systems are present
unique(afiliaciones_sistema$GRUPO)

# Number of observations per system
afiliaciones_sistema %>%
  count(GRUPO) %>%
  arrange(GRUPO)


#=============================================================================
# 
#  FINAL TABLE: AFFILIATIONS BY RIVER BASIN SYSTEM
#
#=============================================================================

afiliaciones_sistema_final <- afiliaciones_sistema %>%
  group_by(GRUPO, sector, año) %>%
  summarise(
    afiliaciones = sum(afiliaciones_asignadas, na.rm = TRUE),
    .groups = "drop"
  )

nrow(afiliaciones_sistema_final)

afiliaciones_sistema_final %>%
  count(GRUPO)

afiliaciones_sistema_final %>%
  arrange(GRUPO, sector, año) %>%
  head(15)

#=============================================================================
# EXAMPLE: "Actividades apoyo a las industrias extractivas"
#=============================================================================

afiliaciones_largo %>%
  filter(
    sector == "Actividades apoyo a las industrias extractivas",
    año == "2025",
    !is.na(afiliaciones),
    afiliaciones > 0
  ) %>%
  arrange(desc(afiliaciones)) %>%
  select(comarca, afiliaciones)


afiliaciones_sistema %>%
  filter(
    sector == "Actividades apoyo a las industrias extractivas",
    año == "2025"
  ) %>%
  select(
    comarca,
    GRUPO,
    afiliaciones,
    peso_poblacion,
    afiliaciones_asignadas
  ) %>%
  arrange(desc(afiliaciones_asignadas))


#=============================================================================
# EXPORT
#=============================================================================

library(openxlsx)

write.xlsx(
  afiliaciones_sistema_final,
  "Output/afiliaciones_sistema_final.xlsx"
)


#=============================================================================
# TOTAL AFFILIATIONS BY SYSTEM AND YEAR
#=============================================================================

afiliaciones_sistema_final %>%
  group_by(GRUPO, año) %>%
  summarise(
    afiliaciones_totales = sum(afiliaciones, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  tidyr::pivot_wider(
    names_from = año,
    values_from = afiliaciones_totales
  )