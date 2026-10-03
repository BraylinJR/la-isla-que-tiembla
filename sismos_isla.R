# La isla que tiembla
# Sismos de magnitud 4 o más en La Española desde 1975, con datos del USGS.
#
# Además de estos paquetes, necesitas tener instalados
# rnaturalearthdata, gifski y av.

library(readr)
library(dplyr)
library(tidyr)
library(lubridate)
library(ggplot2)
library(ggrepel)
library(sf)
library(rnaturalearth)
library(scales)
library(gganimate)

sf_use_s2(FALSE)


# Parámetros ----

inicio  <- "1975-01-01"
mag_min <- 4
zona    <- c(lat_min = 17.3, lat_max = 20.4, lon_min = -74.6, lon_max = -68.2)

fondo   <- "#0d1b2a"
colores <- c("4 a 4.9" = "#c9a227", "5 a 5.9" = "#f4845f", "6 o más" = "#ff2e4c")


# Datos ----

archivo <- "sismos_usgs_raw.csv"

if (!file.exists(archivo)) {
  url <- paste0(
    "https://earthquake.usgs.gov/fdsnws/event/1/query?format=csv",
    "&starttime=", inicio,
    "&endtime=", Sys.Date(),
    "&minmagnitude=", mag_min,
    "&minlatitude=", zona["lat_min"], "&maxlatitude=", zona["lat_max"],
    "&minlongitude=", zona["lon_min"], "&maxlongitude=", zona["lon_max"]
  )
  write_csv(read_csv(url, show_col_types = FALSE), archivo)
}

# Distancia en km entre dos puntos (fórmula de haversine)
distancia_km <- function(lat1, lon1, lat2, lon2) {
  rad <- pi / 180
  a <- sin((lat2 - lat1) * rad / 2)^2 +
    cos(lat1 * rad) * cos(lat2 * rad) * sin((lon2 - lon1) * rad / 2)^2
  2 * 6371 * asin(sqrt(a))
}

sismos <- read_csv(archivo, show_col_types = FALSE) |>
  filter(type == "earthquake") |>
  transmute(
    fecha       = as_datetime(time),
    anio        = year(fecha),
    lat         = latitude,
    lon         = longitude,
    magnitud    = mag,
    lugar       = place,
    nivel       = cut(mag, c(-Inf, 5, 6, Inf), labels = names(colores), right = FALSE),
    km_sd       = distancia_km(lat, lon, 18.4861, -69.9312),
    km_santiago = distancia_km(lat, lon, 19.4517, -70.6970)
  ) |>
  arrange(magnitud)  # así los más fuertes quedan dibujados encima

isla <- ne_countries(
  scale = "medium",
  country = c("Dominican Republic", "Haiti"),
  returnclass = "sf"
)

puntos <- st_as_sf(sismos, coords = c("lon", "lat"), crs = 4326)
sismos$en_tierra <- lengths(st_intersects(puntos, isla)) > 0


# Cifras clave ----

cat("\nSismos de magnitud ", mag_min, " o más desde ", year(inicio), ": ", nrow(sismos), "\n", sep = "")
cat("Magnitud 5 o más:", sum(sismos$magnitud >= 5), "\n")
cat("Magnitud 6 o más:", sum(sismos$magnitud >= 6), "\n")
cat("Ocurrieron en el mar:", percent(mean(!sismos$en_tierra)), "\n")
cat("A menos de 100 km de Santo Domingo:", sum(sismos$km_sd < 100), "\n")
cat("A menos de 100 km de Santiago:", sum(sismos$km_santiago < 100), "\n\n")

sismos |>
  slice_max(magnitud, n = 5) |>
  select(fecha, magnitud, lugar) |>
  print()

# Ojo: el aumento por década refleja mejores instrumentos, no más actividad
sismos |>
  count(decada = anio %/% 10 * 10) |>
  print()


# Elementos del mapa ----

ciudades <- tibble(
  ciudad = c("Santo Domingo", "Santiago"),
  lat    = c(18.4861, 19.4517),
  lon    = c(-69.9312, -70.6970)
)

# Los de 6 o más, uno por día para no repetir réplicas
grandes <- sismos |>
  filter(magnitud >= 6) |>
  mutate(dia = as_date(fecha)) |>
  slice_max(magnitud, n = 1, by = dia, with_ties = FALSE) |>
  mutate(
    sitio    = sub(".* of ", "", lugar),
    sitio    = sub(", Dominican Republic", "", sitio),
    sitio    = sub(", Haiti", " (Haití)", sitio),
    etiqueta = paste0(sitio, " ", anio, " · ", format(magnitud, nsmall = 1))
  )

mapa_base <- list(
  geom_sf(data = isla, fill = "#24303f", color = "#4a5a6e",
          linewidth = 0.3, inherit.aes = FALSE),
  geom_point(aes(size = magnitud, color = nivel, alpha = nivel,
                 group = seq_along(fecha))),
  geom_point(data = ciudades, shape = 21, fill = "white",
             color = fondo, size = 3, stroke = 1),
  geom_text(data = ciudades, aes(label = ciudad), color = "white",
            fontface = "bold", size = 4, nudge_y = -0.13),
  scale_color_manual(values = colores, drop = FALSE),
  scale_alpha_manual(values = c(0.35, 0.75, 0.95), guide = "none"),
  scale_size_continuous(range = c(0.8, 14), limits = c(4, 7.5), guide = "none"),
  guides(color = guide_legend(override.aes = list(size = c(3, 5, 7), alpha = 1))),
  coord_sf(xlim = zona[c("lon_min", "lon_max")],
           ylim = zona[c("lat_min", "lat_max")], expand = FALSE),
  theme_void(base_size = 14),
  theme(
    plot.background = element_rect(fill = fondo, color = NA),
    plot.title      = element_text(color = "white", face = "bold", size = 26),
    plot.subtitle   = element_text(color = "#c9d6e3", size = 15,
                                   margin = margin(t = 4, b = 10)),
    plot.caption    = element_text(color = "#7f93a8", size = 9),
    legend.position = "bottom",
    legend.text     = element_text(color = "white"),
    legend.title    = element_text(color = "white"),
    plot.margin     = margin(20, 20, 15, 20)
  )
)


# Mapa estático ----

mapa <- ggplot(sismos, aes(lon, lat)) +
  mapa_base +
  geom_label_repel(
    data = grandes, aes(label = etiqueta),
    size = 3.6, color = "white", fill = alpha(fondo, 0.85),
    label.size = 0, segment.color = "white", segment.size = 0.3,
    box.padding = 0.8, min.segment.length = 0, seed = 7
  ) +
  labs(
    title    = "La isla que tiembla",
    subtitle = paste(comma(nrow(sismos)), "sismos de magnitud", mag_min,
                     "o más desde", year(inicio)),
    color    = "Magnitud",
    caption  = "Fuente: USGS Earthquake Catalog"
  )

ggsave("mapa_sismos_isla.png", mapa, width = 12, height = 7.5, dpi = 300)


# Animación ----

acumulado <- sismos |>
  count(anio) |>
  complete(anio = min(anio):max(anio), fill = list(n = 0)) |>
  mutate(total = cumsum(n))

anim <- ggplot(sismos, aes(lon, lat)) +
  mapa_base +
  labs(
    title    = "La isla que tiembla",
    subtitle = paste0("Sismos de magnitud ", mag_min, " o más, ",
                      year(inicio), " – ", year(Sys.Date())),
    color    = "Magnitud",
    caption  = "Fuente: USGS Earthquake Catalog",
    tag      = "{round(frame_time)}  ·  {comma(acumulado$total[acumulado$anio == round(frame_time)])} sismos"
  ) +
  theme(
    plot.tag          = element_text(color = "white", face = "bold", size = 20, hjust = 0),
    plot.tag.position = c(0.05, 0.80)
  ) +
  transition_time(anio) +
  shadow_mark(past = TRUE, future = FALSE) +
  enter_grow() +
  enter_fade()

cuadros <- 2 * n_distinct(acumulado$anio)

animate(anim, nframes = cuadros, fps = 10, end_pause = 30,
        width = 1080, height = 1080, res = 130, bg = fondo,
        renderer = gifski_renderer("sismos_isla.gif"))

animate(anim, nframes = cuadros, fps = 10, end_pause = 30,
        width = 1080, height = 1080, res = 130, bg = fondo,
        renderer = av_renderer("sismos_isla.mp4"))
