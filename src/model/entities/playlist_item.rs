use sea_orm::entity::prelude::*;

#[derive(Clone, Debug, PartialEq, Eq, DeriveEntityModel)]
#[sea_orm(table_name = "playlist_item")]
pub struct Model {
    #[sea_orm(primary_key)]
    pub id: i64,
    pub playlist_id: i64,
    pub entry_id: i64,
    pub position: i64,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {
    #[sea_orm(
        belongs_to = "super::playlist::Entity",
        from = "Column::PlaylistId",
        to = "super::playlist::Column::Id",
        on_delete = "Cascade"
    )]
    Playlist,
    #[sea_orm(
        belongs_to = "super::item::Entity",
        from = "Column::EntryId",
        to = "super::item::Column::Id",
        on_delete = "Cascade"
    )]
    Item,
}

impl Related<super::playlist::Entity> for Entity {
    fn to() -> RelationDef {
        Relation::Playlist.def()
    }
}

impl Related<super::item::Entity> for Entity {
    fn to() -> RelationDef {
        Relation::Item.def()
    }
}

impl ActiveModelBehavior for ActiveModel {}
