defmodule Electricbrain.Metrics do
  use Ash.Domain,
    otp_app: :electricbrain

  resources do
    resource Electricbrain.Metrics.Metric
    resource Electricbrain.Metrics.Measurement
    resource Electricbrain.Metrics.HabitMetric
  end
end
