class CharacterSearchCompat < ActiveRecord::Migration[8.1]
  def change
    add_index :ffxiv_characters, :home_world
    add_index :ffxiv_characters, :data_center
    execute "CREATE INDEX index_ffxiv_characters_on_name_fts ON ffxiv_characters USING gin(to_tsvector('simple', name))"  end
end
