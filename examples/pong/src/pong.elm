module Pong exposing (main)

{-|
@docs main
-}

import Random.Pcg
import Dict exposing (Dict)
import Html exposing (Html, div)
import Html.Attributes exposing (style)
import Color exposing (Color)
import Char exposing (toCode)
import AnimationFrame
import Char exposing (KeyCode)
import Keyboard
import Game.TwoD as Game
import Game.TwoD.Render as Render
import Game.TwoD.Camera as Camera exposing (Camera)
import Slime exposing (..)
import Slime.Engine exposing (System, timedSystem, untimedSystem, systemWith, timed, untimed, deletes, cmdsAndDeletes, Listener, listener, Engine)


type alias Rect =
    { x : Float
    , y : Float
    , width : Float
    , height : Float
    , color : Color
    }


collide rect1 rect2 =
    (rect1.x + rect1.width > rect2.x)
        && (rect1.x < rect2.x + rect2.width)
        && (rect1.y + rect1.height > rect2.y)
        && (rect1.y < rect2.y + rect2.height)


type alias Ball =
    { vx : Float, vy : Float }


type alias Paddle =
    { inputState : ( Bool, Bool )
    , inputScheme :
        { up : KeyCode
        , down : KeyCode
        }
    , speed : Float
    }


type alias Score =
    { x : Float
    , y : Float
    , color : Color
    , radius : Float
    , lifetime : Float
    , progress : Float
    }


type alias World =
    EntitySet
        { transforms : ComponentSet Rect
        , balls : ComponentSet Ball
        , paddles : ComponentSet Paddle
        , scores : ComponentSet Score
        , score : ( Int, Int )
        , pcg : Random.Pcg.Seed
        }


type alias Model =
    { world : World
    }


type Msg
    = KeyDown KeyCode
    | KeyUp KeyCode


transforms : ComponentSpec Rect World
transforms =
    { getter = .transforms
    , setter = (\comps world -> { world | transforms = comps })
    }


balls : ComponentSpec Ball World
balls =
    { getter = .balls
    , setter = (\comps world -> { world | balls = comps })
    }


getBall : ( Float, Float, Float, Float ) -> { a : Rect, b : Ball }
getBall ( x, y, vx, vy ) =
    let
        rect =
            { x = x
            , y = y
            , width = 5
            , height = 5
            , color = Color.red
            }

        ball =
            { vx = vx
            , vy = vy
            }
    in
        { a = rect
        , b = ball
        }


spawnBall : ( Float, Float, Float, Float ) -> World -> World
spawnBall spec world =
    let
        ( newEntity, id, uid ) =
            spawnEntity2 transforms balls world (getBall spec)
    in
        newEntity


paddles : ComponentSpec Paddle World
paddles =
    { getter = .paddles
    , setter = (\comps world -> { world | paddles = comps })
    }


scores : ComponentSpec Score World
scores =
    { getter = .scores
    , setter = (\comps world -> { world | scores = comps })
    }


spawnPaddles world =
    let
        paddleSpawner =
            spawnEntities2 transforms paddles

        leftRect =
            { x = 10
            , y = 250
            , width = 10
            , height = 50
            , color = Color.green
            }

        rightRect =
            { x = 480
            , y = 250
            , width = 10
            , height = 50
            , color = Color.green
            }

        leftInput =
            { inputState = ( False, False )
            , inputScheme = { up = toCode 'W', down = toCode 'S' }
            , speed = 200
            }

        rightInput =
            { inputState = ( False, False )
            , inputScheme = { up = toCode 'I', down = toCode 'K' }
            , speed = 200
            }

        ( updatedWorld, ids, uids ) =
            paddleSpawner world
                [ { a = leftRect, b = leftInput }
                , { a = rightRect, b = rightInput }
                ]
    in
        updatedWorld


engine : Engine World Msg
engine =
    let
        deletor =
            deleteEntity transforms
                &-> balls
                &-> paddles
                &-> scores

        systems =
            [ timedSystem moveBalls
            , untimedSystem keepBalls
            , systemWith { timing = untimed, options = deletes } scoreBalls
            , untimedSystem bounceBalls
            , timedSystem movePaddles
            , systemWith { timing = timed, options = deletes } updateScores
            ]

        listeners =
            [ listener setPaddleKeys
            ]
    in
        Slime.Engine.initEngine deletor systems listeners


world : World
world =
    { idSource = Slime.initIdSource
    , transforms = initComponents
    , balls = initComponents
    , paddles = initComponents
    , scores = initComponents
    , score = ( 0, 0 )
    , pcg = Random.Pcg.initialSeed 8675309
    }
        |> spawnBall ( 247.5, 247.5, 100, 80 )
        {- |> spawnBall ( 247.5, 247.5, 80, 100 )
           |> spawnBall ( 247.5, 247.5, -100, 80 )
           |> spawnBall ( 247.5, 247.5, -80, 100 )
           |> spawnBall ( 247.5, 247.5, 100, -80 )
           |> spawnBall ( 247.5, 247.5, 80, -100 )
           |> spawnBall ( 247.5, 247.5, -100, -80 )
           |> spawnBall ( 247.5, 247.5, -80, -100 )
           |> spawnBall ( 40, 230, -80, 100 )
        -}
        |>
            spawnPaddles


model : Model
model =
    { world = world
    }


moveBalls : Float -> World -> World
moveBalls delta =
    let
        addVelocity ball transform delta =
            { transform
                | x = transform.x + ball.vx * delta
                , y = transform.y + ball.vy * delta
            }
    in
        stepEntities (entities2 balls transforms) (\ent2 -> { ent2 | b = addVelocity ent2.a ent2.b delta })


keepBalls : World -> World
keepBalls =
    let
        maybeBounce e2 =
            let
                ball =
                    e2.a

                transform =
                    e2.b
            in
                if transform.x + transform.width >= 500 && ball.vx > 0 then
                    { e2 | a = { ball | vx = -ball.vx }, b = { transform | x = 500 - transform.width } }
                else if transform.x <= 0 && ball.vx < 0 then
                    { e2 | a = { ball | vx = -ball.vx }, b = { transform | x = 0 } }
                else if transform.y + transform.height >= 500 && ball.vy > 0 then
                    { e2 | a = { ball | vy = -ball.vy }, b = { transform | y = 500 - transform.height } }
                else if transform.y <= 0 && ball.vy < 0 then
                    { e2 | a = { ball | vy = -ball.vy }, b = { transform | y = 0 } }
                else
                    e2
    in
        stepEntities (entities2 balls transforms) maybeBounce


updateScores : Float -> World -> ( World, List EntityID )
updateScores deltaTime world =
    let
        stepScore score =
            { score | progress = score.progress + deltaTime }

        updatedWorld =
            stepEntities (entities scores) (\entity -> { entity | a = stepScore entity.a }) world
    in
        ( updatedWorld, List.filter (\e -> e.a.progress > e.a.lifetime) (getEntities scores updatedWorld) |> List.map .id )


scoreBalls : World -> ( World, List EntityID )
scoreBalls world =
    let
        isScored e2 =
            let
                ball =
                    e2.a

                transform =
                    e2.b
            in
                transform.x == 0 || transform.x == 500 - transform.width

        scoreMe e2 =
            let
                transform =
                    e2.b
            in
                { a =
                    { x = transform.x + transform.width / 2
                    , y = transform.y + transform.height / 2
                    , color = Color.blue
                    , radius = 50
                    , lifetime = 1
                    , progress = 0
                    }
                }

        scoredBalls =
            getEntities2 balls transforms world
                |> List.filter isScored

        newScores =
            List.map scoreMe scoredBalls

        updatedScore =
            ( Tuple.first world.score + List.length (List.filter (\score -> score.a.x > 400) newScores)
            , Tuple.second world.score + List.length (List.filter (\score -> score.a.x < 100) newScores)
            )

        newBallSpawn =
            Random.Pcg.list (List.length newScores) (Random.Pcg.int 0 6 |> Random.Pcg.map getNewBall)

        ( newBalls, updatedPcg ) =
            Random.Pcg.step newBallSpawn world.pcg

        ( updatedWorld1, _, _ ) =
            spawnEntities scores world newScores

        ( updatedWorld2, _, _ ) =
            spawnEntities2 transforms balls updatedWorld1 newBalls
    in
        ( { updatedWorld2 | score = updatedScore, pcg = updatedPcg }, List.map .id scoredBalls )


directionToVelocity : Int -> ( Float, Float )
directionToVelocity index =
    case index of
        0 ->
            ( -80, -100 )

        1 ->
            ( 80, -100 )

        2 ->
            ( -80, 100 )

        3 ->
            ( 80, 100 )

        4 ->
            ( 100, 80 )

        _ ->
            ( -80, -100 )


getNewBall : Int -> { a : Rect, b : Ball }
getNewBall dir =
    let
        ( vx, vy ) =
            directionToVelocity dir
    in
        getBall ( 247.5, 247.5, vx, vy )


updateKeyState key isDown paddle =
    if paddle.inputScheme.up == key then
        { paddle | inputState = ( isDown, Tuple.second paddle.inputState ) }
    else if paddle.inputScheme.down == key then
        { paddle | inputState = ( Tuple.first paddle.inputState, isDown ) }
    else
        paddle


setPaddleKeys : Msg -> World -> World
setPaddleKeys msg =
    case msg of
        KeyUp key ->
            stepEntities (entities paddles) (\entity -> { entity | a = (updateKeyState key False entity.a) })

        KeyDown key ->
            stepEntities (entities paddles) (\entity -> { entity | a = (updateKeyState key True entity.a) })


movement : ( Bool, Bool ) -> Float
movement ( up, down ) =
    if up && down then
        0
    else if up then
        1
    else if down then
        -1
    else
        0


movePaddles : Float -> World -> World
movePaddles delta =
    let
        movePaddle e2 =
            let
                paddle =
                    e2.a

                transform =
                    e2.b

                moved =
                    movement paddle.inputState

                newY =
                    (transform.y + delta * moved * paddle.speed)
                        |> clamp 0 450
            in
                if moved /= 0 then
                    { e2 | b = { transform | y = newY } }
                else
                    e2
    in
        stepEntities (entities2 paddles transforms) movePaddle


bounceBalls : World -> World
bounceBalls world =
    let
        bounce e1 e2 =
            let
                paddle =
                    e1.b

                ballVel =
                    e2.a

                ballPos =
                    e2.b
            in
                if collide ballPos paddle then
                    if (ballVel.vx < 0 && ballPos.x < paddle.x + paddle.width) then
                        { e2 | a = { ballVel | vx = -1 * ballVel.vx }, b = { ballPos | x = paddle.x + paddle.width } }
                    else if (ballVel.vx > 0 && ballPos.x + ballPos.width > paddle.x) then
                        { e2 | a = { ballVel | vx = -1 * ballVel.vx }, b = { ballPos | x = paddle.x - ballPos.width } }
                    else
                        e2
                else
                    e2

        paddleList =
            getEntities2 paddles transforms world
    in
        stepEntities (entities2 balls transforms) (\e2 -> List.foldr bounce e2 paddleList) world


renderTransforms =
    Slime.map transforms
        (\transform ->
            Render.shape Render.rectangle
                { color = transform.color
                , position = ( transform.x, transform.y )
                , size = ( transform.width, transform.height )
                }
        )


setAlpha : Color -> Float -> Color
setAlpha color alpha =
    let
        { red, green, blue } =
            Color.toRgb color
    in
        Color.rgba red green blue alpha


lerp : Color -> Color -> Float -> Color
lerp c1 c2 progress =
    let
        rgb1 =
            Color.toRgb c1

        rgb2 =
            Color.toRgb c2

        red =
            round (toFloat rgb1.red + toFloat (rgb2.red - rgb1.red) * progress * progress)

        green =
            round (toFloat rgb1.green + toFloat (rgb2.green - rgb1.green) * progress * progress)

        blue =
            round (toFloat rgb1.blue + toFloat (rgb2.blue - rgb1.blue) * progress * progress)
    in
        Color.rgb red green blue


renderScores =
    Slime.map scores
        (\score ->
            let
                scale =
                    clamp 0 1 (score.progress / score.lifetime)

                size =
                    score.radius * scale
            in
                Render.shape Render.circle
                    { color = lerp score.color Color.white scale
                    , position = ( score.x - size / 2, score.y - size / 2 )
                    , size = ( size, size )
                    }
        )


ui { world } =
    div
        [ style
            [ ( "position", "absolute" )
            , ( "top", "0px" )
            , ( "left", "230px" )
            , ( "width", "40px" )
            , ( "text-align", "center" )
            ]
        ]
        [ Html.text (toString world.score) ]


render ({ world } as model) =
    div
        []
        [ Game.render
            { time = 0
            , camera = Camera.fixedHeight 500 ( 250, 250 )
            , size = ( 500, 500 )
            }
            ((renderTransforms world)
                ++ (renderScores world)
            )
        , ui model
        ]


subs m =
    Sub.batch
        [ Keyboard.downs KeyDown
        , Keyboard.ups KeyUp
        ]


updateWorld =
    Slime.Engine.applySystems engine


takeMessage =
    Slime.Engine.applyListeners engine


update msg model =
    let
        ( updatedWorld, cmds ) =
            Slime.Engine.engineUpdate engine msg model.world
    in
        ( { model
            | world = updatedWorld
          }
        , cmds
        )


{-|
   The game
-}
main : Program Never Model (Slime.Engine.Message Msg)
main =
    Html.program
        { init = model ! []
        , subscriptions = subs >> Slime.Engine.engineSubs
        , update = update
        , view = render
        }
