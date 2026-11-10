use bevy::prelude::*;
use blenvy::BlueprintInfo;

// 🏔️ Componente que identifica entidades com malhas do terreno sólido
#[derive(Component, Default, Reflect)]
#[reflect(Component)]
pub struct TerrainMesh;

// 🚩 Componente marcador da entidade raiz da fase/nível atual carregado
#[derive(Component)]
pub struct LevelRoot;

// 📁 Recurso com o caminho do nível atualmente ativo
#[derive(Resource)]
pub struct CurrentLevel {
    pub path: String,
}

impl Default for CurrentLevel {
    fn default() -> Self {
        Self {
            path: "levels/Scene.glb".to_string(),
        }
    }
}

// 🔄 Evento para solicitar troca de nível/fase em tempo de execução
#[derive(Event)]
pub struct ChangeLevelEvent {
    pub path: String,
}

// 📦 Plugin responsável pelo carregamento e ciclo de vida dos terrenos
pub struct TerrainPlugin;

impl Plugin for TerrainPlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<CurrentLevel>()
            .add_event::<ChangeLevelEvent>()
            .add_systems(Startup, setup_initial_terrain)
            .add_systems(Update, (tag_terrain_meshes, handle_change_level));
    }
}

// Carrega o primeiro terreno definido em CurrentLevel
fn setup_initial_terrain(mut commands: Commands, current_level: Res<CurrentLevel>) {
    spawn_level(&mut commands, &current_level.path);
}

// Spawna a entidade raiz da fase com o BlueprintInfo do Blenvy
pub fn spawn_level(commands: &mut Commands, path: &str) -> Entity {
    commands.spawn((
        LevelRoot,
        BlueprintInfo::from_path(path),
        SpatialBundle::default(),
    )).id()
}

// Identifica recursivamente as malhas que foram instanciadas como parte da cena do terreno
fn tag_terrain_meshes(
    mut commands: Commands,
    level_roots: Query<Entity, With<LevelRoot>>,
    children_query: Query<&Children>,
    unmarked_meshes: Query<Entity, (With<Handle<Mesh>>, Without<TerrainMesh>)>,
) {
    if level_roots.is_empty() { return; }

    for root in &level_roots {
        tag_descendants(root, &children_query, &unmarked_meshes, &mut commands);
    }
}

fn tag_descendants(
    entity: Entity,
    children_query: &Query<&Children>,
    unmarked_meshes: &Query<Entity, (With<Handle<Mesh>>, Without<TerrainMesh>)>,
    commands: &mut Commands,
) {
    if unmarked_meshes.contains(entity) {
        commands.entity(entity).insert(TerrainMesh);
    }

    if let Ok(children) = children_query.get(entity) {
        for child in children.iter() {
            tag_descendants(*child, children_query, unmarked_meshes, commands);
        }
    }
}

// Troca de fase: deleta a árvore da fase antiga e instancia a nova fase
fn handle_change_level(
    mut commands: Commands,
    mut events: EventReader<ChangeLevelEvent>,
    mut current_level: ResMut<CurrentLevel>,
    level_roots: Query<Entity, With<LevelRoot>>,
) {
    for ev in events.read() {
        info!("Trocando de terreno para: {}", ev.path);

        // Descarrega o nível anterior
        for old_root in &level_roots {
            commands.entity(old_root).despawn_recursive();
        }

        // Atualiza recurso e instancia novo nível
        current_level.path = ev.path.clone();
        spawn_level(&mut commands, &current_level.path);
    }
}
