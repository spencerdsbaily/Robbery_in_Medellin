library(dplyr)
library(ranger)
library(forcats)
library(ggplot2)




rob <- read.csv("/Users/daytripperyeahh/Documents/Documents/ongoing_papers/git/Medellin_crime/data/robbery.csv")

## Remove duplicate robbery events
rob <- rob %>%
  distinct(incident_date, latitude, longitude, weapon, .keep_all = TRUE)

## Create binary target
rob <- rob %>%
  mutate(
    weapon_used = factor(
      ifelse(is.na(weapon) | weapon == "None", "No", "Yes"),
      levels = c("No", "Yes")
    )
  )

## Extract time features
rob$incident_date <- as.POSIXct(rob$incident_date, format = "%d/%m/%Y %H:%M")
rob$hour <- as.numeric(format(rob$incident_date, "%H"))
rob$day_of_week <- factor(weekdays(rob$incident_date))

## Build modeling dataset
df_model <- rob %>%
  select(
    weapon_used,
    hour,
    day_of_week,
    sex,
    age,
    marital_status,
    transport_mode,
    neighborhood,
    location,
    item_category
  ) %>%
  mutate(across(where(is.character), as.factor))

## Train/test split
set.seed(42)
train_index <- sample(seq_len(nrow(df_model)), size = 0.8 * nrow(df_model))

train_data <- df_model[train_index, ]
test_data  <- df_model[-train_index, ]

## Handle missing values

# Numeric → median
num_cols <- names(train_data)[sapply(train_data, is.numeric)]
for (col in num_cols) {
  med <- median(train_data[[col]], na.rm = TRUE)
  train_data[[col]][is.na(train_data[[col]])] <- med
  test_data[[col]][is.na(test_data[[col]])] <- med
}

# Factors → "Unknown"
fac_cols <- names(train_data)[sapply(train_data, is.factor)]
for (col in fac_cols) {
  if (!"Unknown" %in% levels(train_data[[col]])) {
    levels(train_data[[col]]) <- c(levels(train_data[[col]]), "Unknown")
  }
  if (!"Unknown" %in% levels(test_data[[col]])) {
    levels(test_data[[col]]) <- c(levels(test_data[[col]]), "Unknown")
  }
  
  train_data[[col]][is.na(train_data[[col]])] <- "Unknown"
  test_data[[col]][is.na(test_data[[col]])] <- "Unknown"
}

## Collapse high-cardinality variables
train_data$neighborhood <- fct_lump_n(train_data$neighborhood, n = 20, other_level = "Other")
test_data$neighborhood  <- fct_other(test_data$neighborhood, keep = levels(train_data$neighborhood))

train_data$location <- fct_lump_n(train_data$location, n = 10, other_level = "Other")
test_data$location  <- fct_other(test_data$location, keep = levels(train_data$location))

## Align factor levels
for (col in fac_cols) {
  test_data[[col]] <- factor(test_data[[col]], levels = levels(train_data[[col]]))
}

## Final cleanup
train_data <- na.omit(train_data)
test_data  <- na.omit(test_data)

train_data$weapon_used <- droplevels(train_data$weapon_used)
test_data$weapon_used  <- droplevels(test_data$weapon_used)

##  Train model with ranger
model <- ranger(
  weapon_used ~ .,
  data = train_data,
  classification = TRUE,
  num.trees = 500,
  importance = "impurity"
)

## Predictions
preds <- predict(model, data = test_data)$predictions

## Evaluation
table(Predicted = preds, Actual = test_data$weapon_used)

## Accuracy
mean(preds == test_data$weapon_used)

## Feature importance
model$variable.importance

###### PLOT ########


importance_df <- data.frame(
  feature = names(model$variable.importance),
  importance = as.numeric(model$variable.importance)
) %>%
  mutate(
    feature = recode(feature,
                     hour = "Hour of Day",
                     day_of_week = "Day of Week",
                     sex = "Sex",
                     age = "Age",
                     marital_status = "Marital Status",
                     transport_mode = "Transport Mode",
                     neighborhood = "Neighborhood",
                     location = "Location Type",
                     item_category = "Item Category"
    ),
    feature = fct_reorder(feature, importance)
  )

ggplot(importance_df, aes(x = importance, y = feature)) +
  geom_col(width = 0.72, fill = "#1F4E79") +
  geom_text(aes(label = round(importance, 1)),
            hjust = -0.12, size = 4, color = "#222222") +
  scale_x_continuous(expand = expansion(mult = c(0, 0.15))) +
  labs(
    title = "What Drives Weapon Use in Robbery Incidents?",
    subtitle = "Feature importance from a Random Forest model built with ranger",
    x = "Importance score",
    y = NULL,
    caption = "Source: Medellin robbery dataset"
  ) +
  theme_minimal(base_size = 14) +
  theme(
    plot.title = element_text(face = "bold", size = 18, color = "#111111"),
    plot.subtitle = element_text(size = 11, color = "#555555"),
    plot.caption = element_text(size = 9, color = "#777777"),
    panel.grid.major.y = element_blank(),
    panel.grid.minor = element_blank(),
    panel.grid.major.x = element_line(color = "#E6E6E6"),
    axis.text.y = element_text(size = 12, color = "#222222"),
    axis.text.x = element_text(size = 11, color = "#222222"),
    plot.margin = ggplot2::margin(15, 20, 15, 15)
  )