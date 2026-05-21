defmodule Electricbrain.Notes do
  use Ash.Domain,
    otp_app: :electricbrain

  resources do
    resource Electricbrain.Notes.Note
    resource Electricbrain.Notes.NoteBlock
  end
end
