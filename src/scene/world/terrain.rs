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
    commands
        .spawn((
            LevelRoot,
            BlueprintInfo::from_path(path),
            SpatialBundle::default(),
        ))
        .id()
}

// Identifica recursivamente as malhas que foram instanciadas como parte da cena do terreno
fn tag_terrain_meshes(
    mut commands: Commands,
    level_roots: Query<Entity, With<LevelRoot>>,
    parents: Query<&Parent>,
    unmarked_meshes: Query<(Entity, Option<&Parent>), (With<Handle<Mesh>>, Without<TerrainMesh>)>,
    added_roots: Query<Entity, Added<LevelRoot>>,
    changed_children: Query<(), Changed<Children>>,
) {
    // A hierarquia só precisa ser percorrida quando surge uma fase ou quando o
    // carregador adiciona/remaneja filhos, não continuamente em cada quadro.
    if added_roots.is_empty() && changed_children.is_empty() {
        return;
    }

    // Examina apenas malhas ainda não identificadas, em vez de percorrer toda a
    // hierarquia do nível em todos os quadros. Caminhar pelos pais também suporta
    // entidades/filhos que o carregador do GLB adicione depois da raiz.
    for (mesh_entity, parent) in &unmarked_meshes {
        let mut ancestor = parent.map(Parent::get);
        while let Some(entity) = ancestor {
            if level_roots.contains(entity) {
                commands.entity(mesh_entity).insert(TerrainMesh);
                break;
            }
            ancestor = parents.get(entity).ok().map(Parent::get);
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
